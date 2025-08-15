output "api_endpoint" {
  description = "Endpoint para POST /event-notification"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/event-notification"
}

output "sqs_queue_url" {
  description = "URL de la cola SQS"
  value       = aws_sqs_queue.events_queue.id
}

output "sqs_queue_arn" {
  description = "ARN de la cola SQS"
  value       = aws_sqs_queue.events_queue.arn
}
