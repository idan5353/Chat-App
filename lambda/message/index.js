const { DynamoDBClient, PutItemCommand, QueryCommand, DeleteItemCommand } = require("@aws-sdk/client-dynamodb");
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require("@aws-sdk/client-apigatewaymanagementapi");

const ddb = new DynamoDBClient({});
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;
const MESSAGES_TABLE = process.env.MESSAGES_TABLE;

exports.handler = async (event) => {
    console.log('📥 Message event received:', JSON.stringify(event, null, 2));
    
    const { domainName, stage, connectionId } = event.requestContext;
    
    let body;
    try {
        body = JSON.parse(event.body || "{}");
        console.log('📄 Parsed body:', body);
    } catch (error) {
        console.error('❌ Invalid JSON in body:', event.body);
        return {
            statusCode: 400,
            body: JSON.stringify({ message: 'Invalid JSON' })
        };
    }
    
    const roomId = body.roomId || "lobby";
    const userId = body.userId || "anonymous";
    const text = String(body.message || "").slice(0, 2000);
    const timestamp = new Date().toISOString();
    
    console.log(`💬 Processing message: "${text}" from ${userId} in room ${roomId}`);
    
    if (!text.trim()) {
        console.log('❌ Empty message received');
        return {
            statusCode: 400,
            body: JSON.stringify({ message: 'Message cannot be empty' })
        };
    }
    
    try {
        // 1. Store message in DynamoDB
        console.log('💾 Storing message in DynamoDB...');
        await ddb.send(new PutItemCommand({
            TableName: MESSAGES_TABLE,
            Item: {
                roomId: { S: roomId },
                timestamp: { S: timestamp },
                userId: { S: userId },
                message: { S: text },
                connectionId: { S: connectionId }
            }
        }));
        console.log('✅ Message stored successfully');
        
        // 2. Get all connections for the room
        console.log(`🔍 Fetching connections for room: ${roomId}`);
        const connections = await ddb.send(new QueryCommand({
            TableName: CONNECTIONS_TABLE,
            KeyConditionExpression: "roomId = :roomId",
            ExpressionAttributeValues: {
                ":roomId": { S: roomId }
            }
        }));
        
        const connectionCount = connections.Items?.length || 0;
        console.log(`📊 Found ${connectionCount} connections in room ${roomId}`);
        
        if (connectionCount === 0) {
            console.log('⚠️ No connections found in room - message stored but not broadcasted');
            return {
                statusCode: 200,
                body: JSON.stringify({ message: 'No active connections in room' })
            };
        }
        
        // 3. Create API Gateway Management client
        const apiEndpoint = `https://${domainName}/${stage}`;
        console.log(`🔗 API Gateway endpoint: ${apiEndpoint}`);
        
        const mgmt = new ApiGatewayManagementApiClient({
            endpoint: apiEndpoint
        });
        
        // 4. Prepare message payload
        const messagePayload = JSON.stringify({
            action: 'message',
            roomId: roomId,
            userId: userId,
            message: text,
            timestamp: timestamp
        });
        
        console.log('📤 Broadcasting message payload:', messagePayload);
        
        // 5. Broadcast to ALL connections (including sender)
        const broadcastPromises = (connections.Items || []).map(async (item) => {
            const connId = item.connectionId.S;
            const connUserId = item.userId?.S || 'unknown';
            
            console.log(`📡 Attempting to send to connection ${connId} (user: ${connUserId})`);
            
            try {
                await mgmt.send(new PostToConnectionCommand({
                    ConnectionId: connId,
                    Data: Buffer.from(messagePayload)
                }));
                console.log(`✅ Message successfully sent to ${connId} (${connUserId})`);
                return { success: true, connectionId: connId };
            } catch (err) {
                console.error(`❌ Failed to send to ${connId} (${connUserId}):`, err);
                
                // If connection is stale (410 Gone), remove it
                if (err?.$metadata?.httpStatusCode === 410) {
                    console.log(`🧹 Removing stale connection: ${connId}`);
                    try {
                        await ddb.send(new DeleteItemCommand({
                            TableName: CONNECTIONS_TABLE,
                            Key: {
                                roomId: { S: roomId },
                                connectionId: { S: connId }
                            }
                        }));
                        console.log(`✅ Stale connection ${connId} removed`);
                    } catch (deleteErr) {
                        console.error(`❌ Failed to remove stale connection:`, deleteErr);
                    }
                }
                return { success: false, connectionId: connId, error: err.message };
            }
        });
        
        // 6. Wait for all broadcasts to complete
        const results = await Promise.allSettled(broadcastPromises);
        const successCount = results.filter(r => r.status === 'fulfilled' && r.value?.success).length;
        
        console.log(`📊 Broadcast results: ${successCount}/${connectionCount} successful`);
        
        // 7. Send confirmation back to sender
        try {
            console.log(`📨 Sending confirmation to sender: ${connectionId}`);
            await mgmt.send(new PostToConnectionCommand({
                ConnectionId: connectionId,
                Data: Buffer.from(JSON.stringify({
                    action: 'messageConfirmation',
                    status: 'sent',
                    timestamp: timestamp,
                    broadcastCount: successCount
                }))
            }));
            console.log('✅ Confirmation sent to sender');
        } catch (err) {
            console.error('❌ Failed to send confirmation to sender:', err);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: 'Message sent successfully',
                broadcastCount: successCount,
                totalConnections: connectionCount
            })
        };
        
    } catch (error) {
        console.error('💥 Error processing message:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ 
                message: 'Failed to send message', 
                error: error.message 
            })
        };
    }
};
