output "websocket_api_endpoint" {
  description = "WebSocket API endpoint URL"
  value       = "${replace(aws_apigatewayv2_api.chat_api.api_endpoint, "wss://", "")}/${aws_apigatewayv2_stage.chat_stage.name}"
}

output "websocket_api_full_endpoint" {
  description = "Full WebSocket API endpoint URL"
  value       = "wss://${replace(aws_apigatewayv2_api.chat_api.api_endpoint, "wss://", "")}/${aws_apigatewayv2_stage.chat_stage.name}"
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.chat_pool.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.chat_client.id
}

output "connections_table_name" {
  description = "DynamoDB connections table name"
  value       = aws_dynamodb_table.connections.name
}

output "messages_table_name" {
  description = "DynamoDB messages table name"
  value       = aws_dynamodb_table.messages.name
}

# Additional outputs
output "cloudfront_distribution_url" {
  description = "CloudFront distribution URL for files"
  value       = aws_cloudfront_distribution.chat_files_cdn.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for file storage"
  value       = aws_s3_bucket.chat_files.bucket
}


