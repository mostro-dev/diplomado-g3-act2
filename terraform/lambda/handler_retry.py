import json
import boto3
import os
import time

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

# Variables de entorno (definidas en Terraform)
TABLE_NAME = os.environ.get("DYNAMODB_TABLE", "vehicle_events")
DLQ_URL = os.environ.get("RETRY_QUEUE_URL")


def lambda_handler(event, context):
    """
    Esta función procesa los mensajes fallidos que llegan a la cola de reintentos (Retry Queue).
    Intenta reinsertarlos en la tabla de DynamoDB. 
    Si vuelve a fallar, se reenvían a la misma cola para otro intento.
    """
    table = dynamodb.Table(TABLE_NAME)

    for record in event["Records"]:
        try:
            body = json.loads(record["body"])
            event_type = body.get("event_type")
            vehicle_id = body.get("vehicle_id", "unknown")

            # Guardamos el evento en DynamoDB
            table.put_item(Item=body)

            print(
                f"[OK] Evento {event_type} para vehículo {vehicle_id} guardado en DynamoDB.")

        except Exception as e:
            print(f"[ERROR] Fallo inesperado: {e}")
            requeue_message(record["body"])

    return {"statusCode": 200, "body": "Retry processing complete."}


def requeue_message(message_body):
    """
    Reenvía el mensaje a la cola de reintentos para volver a procesarlo más tarde.
    """
    try:
        sqs.send_message(
            QueueUrl=DLQ_URL,
            MessageBody=message_body,
            DelaySeconds=10  # Espera antes del próximo intento
        )
        print("[INFO] Mensaje reenviado a la Retry Queue.")
    except Exception as e:
        print(f"[CRITICAL] No se pudo reenviar mensaje a la Retry Queue: {e}")
