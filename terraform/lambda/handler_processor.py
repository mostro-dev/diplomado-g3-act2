import os
import json
import boto3

ses = boto3.client('ses', region_name=os.environ.get(
    "AWS_REGION", "us-east-1"))

SOURCE_EMAIL = os.environ.get("SOURCE_EMAIL")
DESTINATION_EMAIL = os.environ.get("DESTINATION_EMAIL")


def lambda_handler(event, context):
    try:
        for record in event["Records"]:
            body = json.loads(record["body"])

            vehicle_id = body.get("vehicle_id", "Unknown")
            event_type = body.get("event_type", "Unknown")
            description = body.get("description", "")

            subject = f"[Alert] Vehicle {vehicle_id} - {event_type}"
            body_text = f"Vehicle ID: {vehicle_id}\nEvent: {event_type}\nDetails: {description}"

            ses.send_email(
                Source=SOURCE_EMAIL,
                Destination={"ToAddresses": [DESTINATION_EMAIL]},
                Message={
                    "Subject": {"Data": subject},
                    "Body": {"Text": {"Data": body_text}}
                }
            )

        return {"status": "processed"}
    except Exception as e:
        print(f"Error: {str(e)}")
        raise
