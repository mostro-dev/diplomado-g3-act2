import json
import boto3
import os
import uuid
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

# Variables de entorno (definidas en Terraform)
TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME", "vehicle_event_logs")
RETRY_QUEUE_URL = os.environ.get("RETRY_QUEUE_URL")

# Número máximo de reintentos permitidos
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "3"))


def lambda_handler(event, context):
    """
    Procesa los mensajes fallidos de la cola de reintentos (Retry Queue).
    Intenta guardarlos en DynamoDB.
    Si vuelve a fallar, reenvía a la misma cola (con límite de intentos).
    """
    table = dynamodb.Table(TABLE_NAME)

    for record in event["Records"]:
        try:
            body = json.loads(record["body"])

            # Claves obligatorias para DynamoDB
            document_id = body.get("id", str(uuid.uuid4()))
            received_at = body.get(
                "received_at_utc", datetime.now(timezone.utc).isoformat()
            )

            body["id"] = document_id
            body["received_at_utc"] = received_at

            table.put_item(Item=body)

            print(
                f"[OK] Evento {body.get('event_type', 'Unknown')} ({document_id}) guardado en DynamoDB."
            )

        except Exception as e:
            print(f"[ERROR] Fallo inesperado: {e}")
            requeue_message(record["body"])

    return {"statusCode": 200, "body": "Retry processing complete."}


def requeue_message(message_body):
    """
    Reenvía el mensaje a la cola de reintentos para volver a procesarlo más tarde.
    Incrementa el contador de reintentos y lo detiene al superar MAX_RETRIES.
    """
    try:
        body = json.loads(message_body)
        retry_count = body.get("retry_count", 0) + 1

        if retry_count > MAX_RETRIES:
            print(
                f"[CRITICAL] Mensaje descartado tras {retry_count-1} intentos: {body}")
            # Aquí podrías enviarlo a una DLQ final si existe
            return

        body["retry_count"] = retry_count

        sqs.send_message(
            QueueUrl=RETRY_QUEUE_URL,
            MessageBody=json.dumps(body),
            DelaySeconds=10
        )
        print(
            f"[INFO] Mensaje reenviado a la Retry Queue (intento {retry_count}).")

    except Exception as e:
        print(f"[CRITICAL] No se pudo reenviar mensaje a la Retry Queue: {e}")
