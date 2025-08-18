import os
import json
import boto3
from datetime import datetime, timezone

ses = boto3.client('ses', region_name=os.environ.get(
    "AWS_REGION", "us-east-1"))
dynamodb = boto3.resource("dynamodb")

SOURCE_EMAIL = os.environ.get("SOURCE_EMAIL")
DESTINATION_EMAIL = os.environ.get("DESTINATION_EMAIL")
TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME")  # opcional


def lambda_handler(event, context):
    table = None
    if TABLE_NAME:
        table = dynamodb.Table(TABLE_NAME)

    try:
        for record in event["Records"]:
            body = json.loads(record["body"])

            vehicle_plate = body.get("vehicle_plate", "Unknown")
            event_type = body.get("type", "Unknown")
            description = body.get("description", "")
            received_at = body.get("received_at_utc")

            email_sent_at = datetime.now(timezone.utc).isoformat()

            subject = f"[Alert] Vehicle {vehicle_plate} - {event_type}"
            body_text = (
                f"Vehicle Plate: {vehicle_plate}\n"
                f"Event: {event_type}\n"
                f"Details: {description}\n"
                f"Received At (UTC): {received_at}\n"
                f"Email Sent At (UTC): {email_sent_at}\n"
            )

            if event_type.lower() == "emergency":
                ses.send_email(
                    Source=SOURCE_EMAIL,
                    Destination={"ToAddresses": [DESTINATION_EMAIL]},
                    Message={
                        "Subject": {"Data": subject},
                        "Body": {"Text": {"Data": body_text}}
                    }
                )
                print(f"[Processor] Emergency → Email sent at {email_sent_at}")
            else:
                print(
                    f"[Processor] Non-emergency event ({event_type}) → no email sent")

            print(
                f"[Processor] Received at {received_at} → Email sent at {email_sent_at}")

            if table:
                table.put_item(Item={
                    "vehicle_plate": vehicle_plate,
                    "event_type": event_type,
                    "received_at_utc": received_at,
                    "email_sent_at_utc": email_sent_at
                })

        return {"status": "processed"}
    except Exception as e:
        print(f"Error in processor lambda: {e}")
        raise
