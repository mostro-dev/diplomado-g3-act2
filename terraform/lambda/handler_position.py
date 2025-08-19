import os
import json
import boto3
import binascii
import time
import random
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
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
            received_at = body.get(
                "received_at_utc", datetime.now(timezone.utc).isoformat())
            coords = body.get("coordinates", {})
            latitude = coords.get("latitude")
            longitude = coords.get("longitude")

            table.put_item(
                Item={
                    "_id": document_id,
                    "vehicle_plate": vehicle_plate,
                    "event_type": event_type,
                    "received_at_utc": received_at,
                    "latitude": latitude,
                    "longitude": longitude,
                }
            )

            print(f"[Position] Stored event {document_id} for {vehicle_plate}")

        return {"status": "processed"}
    except Exception as e:
        print(f"[Position] Error: {e}")
        raise
