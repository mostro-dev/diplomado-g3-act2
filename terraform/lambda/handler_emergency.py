import os
import json
import boto3
import binascii
import time
import random
from datetime import datetime, timezone

ses = boto3.client("ses", region_name=os.environ.get(
    "AWS_REGION", "us-east-1"))
dynamodb = boto3.resource("dynamodb")

SOURCE_EMAIL = os.environ.get("SOURCE_EMAIL")
DESTINATION_EMAIL = os.environ.get("DESTINATION_EMAIL")
TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME")

_counter = random.randint(0, 0xFFFFFF)


def generate_object_id():
    global _counter
    timestamp = int(time.time())
    random_bytes = os.urandom(5)
    _counter = (_counter + 1) % 0xFFFFFF
    counter_bytes = _counter.to_bytes(3, "big")
    oid = timestamp.to_bytes(4, "big") + random_bytes + counter_bytes
    return binascii.hexlify(oid).decode()


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    try:
        for record in event["Records"]:
            body = json.loads(record["body"])
            document_id = generate_object_id()

            vehicle_plate = body.get("vehicle_plate", "Unknown")
            event_type = body.get("type", "Unknown")
            description = body.get("description", "")
            received_at = body.get(
                "received_at_utc", datetime.now(timezone.utc).isoformat())
            coords = body.get("coordinates", {})
            latitude = coords.get("latitude")
            longitude = coords.get("longitude")

            email_sent_at = datetime.now(timezone.utc).isoformat()
            subject = f"[Alert] Vehicle {vehicle_plate} - {event_type}"
            body_text = (
                f"Vehicle Plate: {vehicle_plate}\n"
                f"Event: {event_type}\n"
                f"Details: {description}\n"
                f"Received At (UTC): {received_at}\n"
                f"Email Sent At (UTC): {email_sent_at}\n"
                f"Latitude: {latitude}, Longitude: {longitude}\n"
            )

            ses.send_email(
                Source=SOURCE_EMAIL,
                Destination={"ToAddresses": [DESTINATION_EMAIL]},
                Message={"Subject": {"Data": subject},
                         "Body": {"Text": {"Data": body_text}}},
            )

            table.put_item(
                Item={
                    "_id": document_id,
                    "vehicle_plate": vehicle_plate,
                    "event_type": event_type,
                    "received_at_utc": received_at,
                    "email_sent_at_utc": email_sent_at,
                    "latitude": latitude,
                    "longitude": longitude,
                }
            )

            print(
                f"[Emergency] Processed event {document_id} for {vehicle_plate}")

        return {"status": "processed"}
    except Exception as e:
        print(f"[Emergency] Error: {e}")
        raise
