import json
import os
import boto3

sqs = boto3.client('sqs')

QUEUE_URL = os.environ.get("SQS_QUEUE_URL")


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))

        # Validar que tenga la información mínima
        if "vehicle_id" not in body or "event_type" not in body:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing vehicle_id or event_type"})
            }

        # Enviar a SQS
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(body)
        )

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Event received"})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
