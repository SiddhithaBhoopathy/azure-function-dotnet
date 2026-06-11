#!/usr/bin/env bash
# OPTION 1 (platform log path): forward the Function App's FunctionAppLogs to Datadog
# via an Azure Monitor diagnostic setting.
#
# These logs are NOT trace-correlated (Azure stamps them in the management plane,
# outside your process). This path is here so you can compare it against the
# Serilog -> Datadog correlated path.
#
# Two destinations are supported. Pick ONE by setting the env var:
#   A) Azure Native Datadog resource (recommended, US3 orgs):
#        export DATADOG_RESOURCE_ID=/subscriptions/.../Microsoft.Datadog/monitors/<name>
#   B) Event Hub + Datadog Forwarder (other sites):
#        export EVENT_HUB_AUTH_RULE_ID=/subscriptions/.../authorizationRules/RootManageSharedAccessKey
#        export EVENT_HUB_NAME=<hub name>
#
# Usage: ./03-diagnostic-settings.sh

cd "$(dirname "$0")"
source ./00-config.sh

FUNCTION_APP_ID="$(az functionapp show \
  --name "$FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)"

LOGS_JSON='[{"category":"FunctionAppLogs","enabled":true}]'

if [[ -n "${DATADOG_RESOURCE_ID:-}" ]]; then
  echo ">> Creating diagnostic setting -> Datadog native resource..."
  az monitor diagnostic-settings create \
    --name "to-datadog" \
    --resource "$FUNCTION_APP_ID" \
    --partner-solution "$DATADOG_RESOURCE_ID" \
    --logs "$LOGS_JSON" \
    -o none
elif [[ -n "${EVENT_HUB_AUTH_RULE_ID:-}" && -n "${EVENT_HUB_NAME:-}" ]]; then
  echo ">> Creating diagnostic setting -> Event Hub (Datadog Forwarder)..."
  az monitor diagnostic-settings create \
    --name "to-datadog" \
    --resource "$FUNCTION_APP_ID" \
    --event-hub-rule "$EVENT_HUB_AUTH_RULE_ID" \
    --event-hub "$EVENT_HUB_NAME" \
    --logs "$LOGS_JSON" \
    -o none
else
  echo "ERROR: set DATADOG_RESOURCE_ID (native) or EVENT_HUB_AUTH_RULE_ID + EVENT_HUB_NAME." >&2
  echo "Alternatively, use Datadog's automated log forwarding ARM template from the" >&2
  echo "Azure integration tile (Integrations > Azure > Configure Log Forwarding)." >&2
  exit 1
fi

echo "Diagnostic setting 'to-datadog' created for $FUNCTION_APP."
echo "FunctionAppLogs will appear in Datadog Log Explorer (source: azure.functions)."
