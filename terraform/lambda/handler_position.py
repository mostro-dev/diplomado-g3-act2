import os
import json
import boto3
import uuid
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME")


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    try:
        for record in event["Records"]:
            body = json.loads(record["body"])

            # Usamos el id que viene del intake, si existe; si no, generamos uno nuevo
            document_id = body.get("id", str(uuid.uuid4()))

            vehicle_plate = body.get("vehicle_plate", "Unknown")
            event_type = body.get("type", "Unknown")
            received_at = body.get(
                "received_at_utc", datetime.now(timezone.utc).isoformat()
            )
            coords = body.get("coordinates", {})
            latitude = coords.get("latitude")
            longitude = coords.get("longitude")

            table.put_item(
                Item={
                    "id": document_id,
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
