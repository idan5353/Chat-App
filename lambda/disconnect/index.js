const { DynamoDBClient, DeleteItemCommand, QueryCommand } = require("@aws-sdk/client-dynamodb");

const ddb = new DynamoDBClient({});
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;

exports.handler = async (event) => {
    console.log('Disconnect event:', JSON.stringify(event, null, 2));
    
    const connectionId = event.requestContext.connectionId;
    
    try {
        // First, find the connection to get the roomId
        const scanCommand = new QueryCommand({
            TableName: CONNECTIONS_TABLE,
            IndexName: "ConnectionIndex", // You might need to create this GSI
            KeyConditionExpression: "connectionId = :connId",
            ExpressionAttributeValues: {
                ":connId": { S: connectionId }
            }
        });
        
        // Alternative: scan all partitions (less efficient but works without GSI)
        const connections = await ddb.send(new QueryCommand({
            TableName: CONNECTIONS_TABLE,
            FilterExpression: "connectionId = :connId",
            ExpressionAttributeValues: {
                ":connId": { S: connectionId }
            }
        }));
        
        if (connections.Items && connections.Items.length > 0) {
            const roomId = connections.Items[0].roomId.S;
            
            await ddb.send(new DeleteItemCommand({
                TableName: CONNECTIONS_TABLE,
                Key: {
                    roomId: { S: roomId },
                    connectionId: { S: connectionId }
                }
            }));
            
            console.log(`Connection removed: ${connectionId} from room: ${roomId}`);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Disconnected successfully' })
        };
        
    } catch (error) {
        console.error('Error removing connection:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: 'Failed to disconnect', error: error.message })
        };
    }
};
