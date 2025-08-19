import json
import os
import boto3
from datetime import datetime, timezone

sqs = boto3.client("sqs")
EMERGENCY_QUEUE_URL = os.environ.get("EMERGENCY_QUEUE_URL")
POSITION_QUEUE_URL = os.environ.get("POSITION_QUEUE_URL")


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))

        if "vehicle_plate" not in body or "type" not in body:
            print("[Intake] Missing vehicle_plate or type in body")

        body["received_at_utc"] = datetime.now(timezone.utc).isoformat()

        event_type = body["type"].lower()
        target_queue = EMERGENCY_QUEUE_URL if event_type == "emergency" else POSITION_QUEUE_URL

        sqs.send_message(QueueUrl=target_queue, MessageBody=json.dumps(body))

        print(
            f"[Intake] Routed {event_type} event for {body['vehicle_plate']} to {target_queue}")

        return {"statusCode": 200, "body": json.dumps({"message": "Event routed"})}
    except Exception as e:
        print(f"[Intake] Error: {str(e)}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
