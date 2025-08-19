# Reto 2

## Utilidades DB

### Dumpear la tabla

```zsh
aws dynamodb scan --table-name vehicle_event_logs --output json > dump.json
```

### Resetear la tabla

```zsh
aws dynamodb scan --table-name vehicle_event_logs --attributes-to-get id --query "Items[].id.S" --output text | \
while read id; do
  aws dynamodb delete-item --table-name vehicle_event_logs --key "{\"id\": {\"S\": \"$id\"}}"
done
```

## Correr el proyecto

- Añadir un user a IAM y obtener key, secret key, darle permisos de administrador.
- Configurar aws cli para ese usuario
- Instalar terraform

### Terraform

Para ver que el archivo terraform está bien formado y no dará problemas al subir a PROD.

```zsh
terraform plan
```

Para subir los cambios a prod.

```zsh
terrafom apply
```

Para destruir todos los servicios de AWS y no incurrir en gastos extra.

```zsh
terrafom destroy
```

## Correr K6

```zsh
k6 run ./k6/k6-script.js
```
