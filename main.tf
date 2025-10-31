terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Archive Lambda functions
data "archive_file" "connect_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/connect"
  output_path = "${path.module}/connect.zip"
}

data "archive_file" "disconnect_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/disconnect"
  output_path = "${path.module}/disconnect.zip"
}

data "archive_file" "message_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/message"
  output_path = "${path.module}/message.zip"
}

# NEW: Additional archive files for enhanced features
data "archive_file" "ai_assistant_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ai-assistant"
  output_path = "${path.module}/ai-assistant.zip"
}

data "archive_file" "file_upload_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/file_upload"
  output_path = "${path.module}/file-upload.zip"
}

data "archive_file" "notification_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/notifications"
  output_path = "${path.module}/notifications.zip"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "chat_pool" {
  name = "${var.project_name}-user-pool"

  username_attributes = ["email"]
  
  # Enable email verification
  auto_verified_attributes = ["email"]
  
  # Email configuration for verification emails
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Configure verification messages
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "DevOps Chat - Verify your email"
    email_message        = "Your verification code for DevOps Chat is {####}"
  }

  # Only specify email as required in schema
  schema {
    name                = "email"
    required            = true
    mutable             = true
    attribute_data_type = "String"
  }

  # Add given_name as optional
  schema {
    name                = "given_name"
    required            = false
    mutable             = true
    attribute_data_type = "String"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client with correct auth flows
resource "aws_cognito_user_pool_client" "chat_client" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.chat_pool.id

  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_PASSWORD_AUTH", 
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]
  
  # Standard attributes that can be read and written
  read_attributes  = ["email", "email_verified", "given_name", "family_name", "name"]
  write_attributes = ["email", "given_name", "family_name", "name"]
}

# DynamoDB Tables
resource "aws_dynamodb_table" "connections" {
  name           = "${var.project_name}-connections"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "roomId"
  range_key      = "connectionId"

  attribute {
    name = "roomId"
    type = "S"
  }

  attribute {
    name = "connectionId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "messages" {
  name           = "${var.project_name}-messages"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "roomId"
  range_key      = "timestamp"

  attribute {
    name = "roomId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Random string for unique resource names
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket for file uploads
resource "aws_s3_bucket" "chat_files" {
  bucket = "${var.project_name}-chat-files-${random_string.bucket_suffix.result}"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "chat_files_versioning" {
  bucket = aws_s3_bucket.chat_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chat_files_encryption" {
  bucket = aws_s3_bucket.chat_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "chat_files_pab" {
  bucket = aws_s3_bucket.chat_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "Chat files OAI"
}

# S3 bucket policy for CloudFront
resource "aws_s3_bucket_policy" "chat_files_policy" {
  bucket = aws_s3_bucket.chat_files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.chat_files.arn}/*"
      }
    ]
  })
}

# CloudFront distribution for fast file delivery
resource "aws_cloudfront_distribution" "chat_files_cdn" {
  origin {
    domain_name = aws_s3_bucket.chat_files.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.chat_files.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.chat_files.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM role for API Gateway CloudWatch logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach the AWS managed policy for API Gateway CloudWatch logging
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Set the CloudWatch role for API Gateway account settings
resource "aws_api_gateway_account" "api_gateway_account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
  
  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch_logs]
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Enhanced Lambda policy with S3 access
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy"
  description = "IAM policy for chat app lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.connections.arn,
          "${aws_dynamodb_table.connections.arn}/index/*",
          aws_dynamodb_table.messages.arn,
          "${aws_dynamodb_table.messages.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.chat_files.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# IAM role for AI Lambda with Bedrock access
resource "aws_iam_role" "lambda_ai_role" {
  name = "${var.project_name}-lambda-ai-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Policy for Bedrock access
resource "aws_iam_policy" "bedrock_policy" {
  name = "${var.project_name}-bedrock-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.connections.arn,
          aws_dynamodb_table.messages.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_policy_attachment" {
  role       = aws_iam_role.lambda_ai_role.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

# Lambda functions
resource "aws_lambda_function" "connect_handler" {
  filename         = data.archive_file.connect_zip.output_path
  function_name    = "${var.project_name}-connect"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs20.x"
  timeout         = 30

  source_code_hash = data.archive_file.connect_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "disconnect_handler" {
  filename         = data.archive_file.disconnect_zip.output_path
  function_name    = "${var.project_name}-disconnect"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs20.x"
  timeout         = 30

  source_code_hash = data.archive_file.disconnect_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "message_handler" {
  filename         = data.archive_file.message_zip.output_path
  function_name    = "${var.project_name}-message"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs20.x"
  timeout         = 30

  source_code_hash = data.archive_file.message_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      MESSAGES_TABLE    = aws_dynamodb_table.messages.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# AI Assistant Lambda
resource "aws_lambda_function" "ai_assistant" {
  filename         = data.archive_file.ai_assistant_zip.output_path
  function_name    = "${var.project_name}-ai-assistant"
  role            = aws_iam_role.lambda_ai_role.arn
  handler         = "index.handler"
  runtime         = "nodejs20.x"
  timeout         = 60

  source_code_hash = data.archive_file.ai_assistant_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      MESSAGES_TABLE    = aws_dynamodb_table.messages.name
      BEDROCK_MODEL_ID  = "anthropic.claude-3-sonnet-20240229-v1:0"
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# File upload Lambda
resource "aws_lambda_function" "file_upload" {
  filename         = data.archive_file.file_upload_zip.output_path
  function_name    = "${var.project_name}-file-upload"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs20.x"
  timeout         = 30

  source_code_hash = data.archive_file.file_upload_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.chat_files.bucket
      CDN_URL     = aws_cloudfront_distribution.chat_files_cdn.domain_name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# WebSocket API
resource "aws_apigatewayv2_api" "chat_api" {
  name                       = "${var.project_name}-websocket-api"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# WebSocket Stage
resource "aws_apigatewayv2_stage" "chat_stage" {
  api_id      = aws_apigatewayv2_api.chat_api.id
  name        = var.environment
  auto_deploy = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
  
  depends_on = [aws_api_gateway_account.api_gateway_account]
}

# Lambda Integrations
resource "aws_apigatewayv2_integration" "connect_integration" {
  api_id           = aws_apigatewayv2_api.chat_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.connect_handler.invoke_arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration" {
  api_id           = aws_apigatewayv2_api.chat_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.disconnect_handler.invoke_arn
}

resource "aws_apigatewayv2_integration" "message_integration" {
  api_id           = aws_apigatewayv2_api.chat_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.message_handler.invoke_arn
}

# Routes
resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.chat_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.chat_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration.id}"
}

resource "aws_apigatewayv2_route" "message_route" {
  api_id    = aws_apigatewayv2_api.chat_api.id
  route_key = "sendMessage"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.chat_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

# Lambda Permissions
resource "aws_lambda_permission" "connect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connect_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "disconnect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disconnect_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "message_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat_api.execution_arn}/*/*"
}

# FIXED: EventBridge resources (correct resource names)
resource "aws_cloudwatch_event_rule" "ai_trigger" {
  name = "${var.project_name}-ai-trigger"

  event_pattern = jsonencode({
    source      = ["chat.message"]
    detail-type = ["New Message"]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "ai_target" {
  rule      = aws_cloudwatch_event_rule.ai_trigger.name
  target_id = "AiAssistantTarget"
  arn       = aws_lambda_function.ai_assistant.arn
}

resource "aws_lambda_permission" "allow_eventbridge_ai" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ai_assistant.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ai_trigger.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "connect_logs" {
  name              = "/aws/lambda/${aws_lambda_function.connect_handler.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "disconnect_logs" {
  name              = "/aws/lambda/${aws_lambda_function.disconnect_handler.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "message_logs" {
  name              = "/aws/lambda/${aws_lambda_function.message_handler.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "ai_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ai_assistant.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "file_upload_logs" {
  name              = "/aws/lambda/${aws_lambda_function.file_upload.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "chat_dashboard" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.message_handler.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.message_handler.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.message_handler.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Chat Lambda Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.chat_files.bucket, "StorageType", "StandardStorage"],
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.chat_files.bucket, "StorageType", "AllStorageTypes"]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Storage Metrics"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "120"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"

  dimensions = {
    FunctionName = aws_lambda_function.message_handler.function_name
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
