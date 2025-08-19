terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ===================================================================================
# IAM ROLES
# ===================================================================================

resource "aws_iam_role" "lambda_role" {
  name = "lambda_vehicle_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_ses" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

# ===================================================================================
# SQS
# ===================================================================================

resource "aws_sqs_queue" "emergency_queue" {
  name                       = "emergency-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
}

resource "aws_sqs_queue" "position_queue" {
  name                       = "position-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
}

resource "aws_sqs_queue" "retry_queue" {
  name                       = "retry-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
}

# ===================================================================================
# IAM POLICIES for SQS
# ===================================================================================

resource "aws_iam_policy" "sqs_send_policy" {
  name        = "lambda_sqs_send_policy"
  description = "Allow Lambda Intake & Retry Processor to send messages to SQS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["sqs:SendMessage", "sqs:SendMessageBatch"],
      Resource = [
        aws_sqs_queue.emergency_queue.arn,
        aws_sqs_queue.position_queue.arn,
        aws_sqs_queue.retry_queue.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_send_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_send_policy.arn
}

resource "aws_iam_policy" "sqs_receive_policy" {
  name        = "lambda_sqs_receive_policy"
  description = "Allow Lambda Processors to read messages from SQS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      Resource = [
        aws_sqs_queue.emergency_queue.arn,
        aws_sqs_queue.position_queue.arn,
        aws_sqs_queue.retry_queue.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_receive_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_receive_policy.arn
}

# ===================================================================================
# DYNAMODB TABLE
# ===================================================================================

resource "aws_dynamodb_table" "event_logs" {
  name         = "vehicle_event_logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  range_key    = "received_at_utc"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "received_at_utc"
    type = "S"
  }

  tags = {
    Environment = "prod"
    Project     = "vehicle-events"
  }
}

resource "aws_iam_policy" "dynamodb_write_policy" {
  name        = "lambda_dynamodb_write_policy"
  description = "Allow Lambda Processors to write logs to DynamoDB"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
      ],
      Resource = aws_dynamodb_table.event_logs.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_write_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_write_policy.arn
}

# ===================================================================================
# LAMBDA: INTAKE
# ===================================================================================

resource "aws_lambda_function" "intake" {
  function_name = "vehicle_events_intake"
  runtime       = "python3.12"
  handler       = "handler_intake.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda_intake.zip"
  timeout       = 5

  environment {
    variables = {
      EMERGENCY_QUEUE_URL = aws_sqs_queue.emergency_queue.url
      POSITION_QUEUE_URL  = aws_sqs_queue.position_queue.url
      RETRY_QUEUE_URL     = aws_sqs_queue.retry_queue.url
    }
  }
}

# ===================================================================================
# LAMBDAS: PROCESSORS
# ===================================================================================

resource "aws_lambda_function" "emergency_processor" {
  function_name = "emergency_events_processor"
  runtime       = "python3.12"
  handler       = "handler_emergency.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda_emergency.zip"
  timeout       = 30

  environment {
    variables = {
      SOURCE_EMAIL      = var.source_email
      DESTINATION_EMAIL = var.destination_email
      DYNAMO_TABLE_NAME = aws_dynamodb_table.event_logs.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_emergency" {
  event_source_arn                   = aws_sqs_queue.emergency_queue.arn
  function_name                      = aws_lambda_function.emergency_processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 0
  enabled                            = true

  scaling_config {
    maximum_concurrency = 6
  }
}

resource "aws_lambda_function" "position_processor" {
  function_name = "position_events_processor"
  runtime       = "python3.12"
  handler       = "handler_position.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda_position.zip"
  timeout       = 30

  environment {
    variables = {
      DYNAMO_TABLE_NAME = aws_dynamodb_table.event_logs.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_position" {
  event_source_arn                   = aws_sqs_queue.position_queue.arn
  function_name                      = aws_lambda_function.position_processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 0
  enabled                            = true

  scaling_config {
    maximum_concurrency = 6
  }
}

# ===================================================================================
# LAMBDA: RETRY PROCESSOR
# ===================================================================================

resource "aws_lambda_function" "retry_processor" {
  function_name = "retry_events_processor"
  runtime       = "python3.12"
  handler       = "handler_retry.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda_retry.zip"
  timeout       = 30

  environment {
    variables = {
      EMERGENCY_QUEUE_URL = aws_sqs_queue.emergency_queue.url
      POSITION_QUEUE_URL  = aws_sqs_queue.position_queue.url
      RETRY_QUEUE_URL     = aws_sqs_queue.retry_queue.url
      DYNAMODB_TABLE      = aws_dynamodb_table.event_logs.name
      DYNAMO_TABLE_NAME   = aws_dynamodb_table.event_logs.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_retry" {
  event_source_arn                   = aws_sqs_queue.retry_queue.arn
  function_name                      = aws_lambda_function.retry_processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 10
  enabled                            = true

  scaling_config {
    maximum_concurrency = 2
  }
}

# ===================================================================================
# API GATEWAY + LOGGING
# ===================================================================================

resource "aws_cloudwatch_log_group" "apigw_access_logs" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.http_api.name}-access"
  retention_in_days = 3
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "vehicle-events-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_intake_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.intake.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "event_notification" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /event-notification"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_intake_integration.id}"
}

resource "aws_lambda_permission" "apigw_invoke_intake" {
  statement_id  = "AllowAPIGatewayInvokeIntake"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intake.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access_logs.arn
    format = jsonencode({
      requestId               = "$context.requestId",
      ip                      = "$context.identity.sourceIp",
      requestTime             = "$context.requestTime",
      httpMethod              = "$context.httpMethod",
      routeKey                = "$context.routeKey",
      status                  = "$context.status",
      protocol                = "$context.protocol",
      responseLength          = "$context.responseLength",
      errorMessage            = "$context.error.message",
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_rate_limit  = 15
    throttling_burst_limit = 2000
  }
}
