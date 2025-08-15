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
  name = "lambda_emergency_role"

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

resource "aws_iam_policy" "sqs_send_policy" {
  name        = "lambda_sqs_send_policy"
  description = "Allow Lambda Intake to send messages to SQS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["sqs:SendMessage", "sqs:SendMessageBatch"],
      Resource = aws_sqs_queue.events_queue.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_send_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_send_policy.arn
}

resource "aws_iam_policy" "sqs_receive_policy" {
  name        = "lambda_sqs_receive_policy"
  description = "Allow Lambda Processor to read messages from SQS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      Resource = aws_sqs_queue.events_queue.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_receive_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sqs_receive_policy.arn
}


# ===================================================================================
# SQS
# ===================================================================================

resource "aws_sqs_queue" "events_dlq" {
  name                      = "vehicle-events-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "events_queue" {
  name                       = "vehicle-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 5
  })
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
      SQS_QUEUE_URL = aws_sqs_queue.events_queue.id
    }
  }

  # reserved_concurrent_executions = var.intake_reserved_concurrency
}

# ===================================================================================
# LAMBDA: PROCESSOR
# ===================================================================================

resource "aws_lambda_function" "processor" {
  function_name = "vehicle_events_processor"
  runtime       = "python3.12"
  handler       = "handler_processor.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/lambda_processor.zip"
  timeout       = 30

  environment {
    variables = {
      SOURCE_EMAIL      = var.source_email
      DESTINATION_EMAIL = var.destination_email
    }
  }

  # reserved_concurrent_executions = var.processor_reserved_concurrency
}

resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  event_source_arn                   = aws_sqs_queue.events_queue.arn
  function_name                      = aws_lambda_function.processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 0
  enabled                            = true
}

# ===================================================================================
# API GATEWAY
# ===================================================================================

resource "aws_apigatewayv2_api" "http_api" {
  name          = "emergency-events-api"
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
}

# ===================================================================================
# WAF (temporalmente sin asociación para evitar error en API Gateway v2)
# ===================================================================================

resource "aws_wafv2_web_acl" "rate_limit_acl" {
  name        = "rate-limit-15-rps"
  scope       = "REGIONAL"
  description = "Limit 15 requests per second per IP"

  default_action {
    allow {}
  }

  rule {
    name     = "Limit15RPS"
    priority = 1

    statement {
      rate_based_statement {
        limit              = 900
        aggregate_key_type = "IP"
      }
    }

    action {
      block {}
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "Limit15RPS"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "RateLimitACL"
  }
}
