output "api_endpoint" {
  description = "Endpoint base de la API"
  value       = aws_apigatewayv2_stage.prod.invoke_url
}

output "api_event_notification_url" {
  description = "Endpoint completo para invocar /event-notification"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/event-notification"
}

# ===================================================================================
# SQS QUEUES
# ===================================================================================

output "emergency_queue_url" {
  description = "URL de la cola de emergencias"
  value       = aws_sqs_queue.emergency_queue.id
}

output "emergency_queue_arn" {
  description = "ARN de la cola de emergencias"
  value       = aws_sqs_queue.emergency_queue.arn
}

output "position_queue_url" {
  description = "URL de la cola de posiciones"
  value       = aws_sqs_queue.position_queue.id
}

output "position_queue_arn" {
  description = "ARN de la cola de posiciones"
  value       = aws_sqs_queue.position_queue.arn
}

output "retry_queue_url" {
  description = "URL de la cola de reintentos"
  value       = aws_sqs_queue.retry_queue.id
}

output "retry_queue_arn" {
  description = "ARN de la cola de reintentos"
  value       = aws_sqs_queue.retry_queue.arn
}

# ===================================================================================
# DynamoDB
# ===================================================================================

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB de logs"
  value       = aws_dynamodb_table.event_logs.name
}

output "dynamodb_table_arn" {
  description = "ARN de la tabla DynamoDB de logs"
  value       = aws_dynamodb_table.event_logs.arn
}
