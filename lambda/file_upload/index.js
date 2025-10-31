const { S3Client, PutObjectCommand, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

const s3 = new S3Client({});
const BUCKET_NAME = process.env.BUCKET_NAME;

exports.handler = async (event) => {
    console.log('File upload event:', JSON.stringify(event, null, 2));
    
    const { httpMethod, body } = event;
    
    if (httpMethod === 'POST') {
        try {
            const { fileName, fileType } = JSON.parse(body);
            const fileKey = `uploads/${Date.now()}-${fileName}`;
            
            // Generate presigned URL for upload
            const command = new PutObjectCommand({
                Bucket: BUCKET_NAME,
                Key: fileKey,
                ContentType: fileType
            });
            
            const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 3600 });
            
            return {
                statusCode: 200,
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "Content-Type",
                    "Access-Control-Allow-Methods": "POST"
                },
                body: JSON.stringify({
                    uploadUrl: uploadUrl,
                    fileKey: fileKey
                })
            };
            
        } catch (error) {
            console.error('Error generating upload URL:', error);
            return {
                statusCode: 500,
                body: JSON.stringify({ error: error.message })
            };
        }
    }
    
    return {
        statusCode: 405,
        body: JSON.stringify({ error: 'Method not allowed' })
    };
};
