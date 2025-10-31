const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");

const ddb = new DynamoDBClient({});
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE;

exports.handler = async (event) => {
    console.log('Connect event:', JSON.stringify(event, null, 2));
    
    const roomId = event.queryStringParameters?.roomId || "lobby";
    const userId = event.queryStringParameters?.userId || "anonymous";
    const connectionId = event.requestContext.connectionId;
    const connectedAt = new Date().toISOString();
    
    // TTL set to 24 hours from now
    const ttl = Math.floor(Date.now() / 1000) + (24 * 60 * 60);
    
    try {
        await ddb.send(new PutItemCommand({
            TableName: CONNECTIONS_TABLE,
            Item: {
                roomId: { S: roomId },
                connectionId: { S: connectionId },
                userId: { S: userId },
                connectedAt: { S: connectedAt },
                ttl: { N: String(ttl) }
            }
        }));
        
        console.log(`Connection stored: ${connectionId} for room: ${roomId}`);
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Connected successfully' })
        };
        
    } catch (error) {
        console.error('Error storing connection:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: 'Failed to connect', error: error.message })
        };
    }
};
