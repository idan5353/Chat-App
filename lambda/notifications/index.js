// Simple notification handler
exports.handler = async (event) => {
    console.log('Notification event:', JSON.stringify(event, null, 2));
    
    // Process notification logic here
    return {
        statusCode: 200,
        body: JSON.stringify({ message: 'Notification processed' })
    };
};
