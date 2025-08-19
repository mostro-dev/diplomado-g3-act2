## Dumpear la table

```zsh
aws dynamodb scan --table-name vehicle_event_logs --output json > dump.json
```

## Resetear la tabla

```zsh
aws dynamodb scan --table-name vehicle_event_logs --attributes-to-get \_id --query "Items[].[_id.S]" --output text | \
while read id; do
aws dynamodb delete-item --table-name vehicle_event_logs --key "{\"\_id\": {\"S\": \"$id\"}}"
done
```
