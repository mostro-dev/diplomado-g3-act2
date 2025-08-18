import json
import os
import boto3
from datetime import datetime, timezone

sqs = boto3.client('sqs')
QUEUE_URL = os.environ.get("SQS_QUEUE_URL")


def lambda_handler(event, context):
    print("[Intake] STARTING", json.dumps(event))
    try:
        body = json.loads(event.get("body", "{}"))
        print("[Intake] Parsed body:", json.dumps(body))

        # Validar que tenga la información mínima del k6
        if "vehicle_plate" not in body or "type" not in body:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing vehicle_plate or type"})
            }

        # Agregar timestamp para trazabilidad
        body["received_at_utc"] = datetime.now(timezone.utc).isoformat()

        # Enviar a SQS
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(body)
        )

        print(
            f"[Intake] Received event for vehicle {body['vehicle_plate']} at {body['received_at_utc']} UTC")

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Event received"})
        }

    except Exception as e:
        print(f"[Intake] Error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
