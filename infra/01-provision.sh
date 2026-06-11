#!/usr/bin/env bash
# Provisions the target configuration:
#   - Linux Dedicated (App Service) plan
#   - .NET 9 Isolated Worker Function App
# Then applies all Datadog app settings (APM tracer attach + intake + tagging).
#
# Usage:
#   export DD_API_KEY=<your key>
#   ./01-provision.sh

cd "$(dirname "$0")"
source ./00-config.sh

if [[ -z "$DD_API_KEY" ]]; then
  echo "ERROR: DD_API_KEY is not set. Run: export DD_API_KEY=<your key>" >&2
  exit 1
fi

echo ">> Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

echo ">> Creating storage account..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  -o none

echo ">> Creating Linux Dedicated (App Service) plan [$PLAN_SKU]..."
# --is-linux makes this a Linux plan; a non-elastic SKU (P1V3/S1) makes it Dedicated,
# which is what distinguishes it from Premium (EP*) or Consumption (Y1).
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --is-linux \
  --sku "$PLAN_SKU" \
  -o none

echo ">> Creating the Function App (Linux, $RUNTIME $RUNTIME_VERSION)..."
az functionapp create \
  --name "$FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --plan "$APP_SERVICE_PLAN" \
  --runtime "$RUNTIME" \
  --runtime-version "$RUNTIME_VERSION" \
  --functions-version "$FUNCTIONS_VERSION" \
  --os-type Linux \
  -o none

echo ">> Applying Datadog application settings..."
# These two groups are the heart of the reproduction:
#   (a) CORECLR_* + DD_DOTNET_TRACER_HOME  -> attaches the Datadog .NET tracer to the
#       isolated worker process for automatic APM instrumentation (Linux paths).
#   (b) DD_API_KEY / DD_SITE / tagging     -> where + how telemetry is sent.
#   (c) DD_LOGS_INJECTION=true             -> stamps dd_trace_id/dd_span_id into logs so
#       the correlated log path links to traces.
#   (d) DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger -> the FIX (Path A), config-only:
#       the tracer's automatic instrumentation ships Microsoft.Extensions.Logging (ILogger)
#       logs straight to the Datadog intake over HTTPS (URL derived from DD_SITE). No NuGet
#       sink, no app code. These arrive with dd.trace_id and correlate with the traces.
#       Comment this line out to fall back to forwarder-only logs (the customer's repro).
az functionapp config appsettings set \
  --name "$FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    CORECLR_ENABLE_PROFILING=1 \
    "CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8}" \
    "CORECLR_PROFILER_PATH=/home/site/wwwroot/datadog/linux-x64/Datadog.Trace.ClrProfiler.Native.so" \
    "DD_DOTNET_TRACER_HOME=/home/site/wwwroot/datadog" \
    "DD_API_KEY=$DD_API_KEY" \
    "DD_SITE=$DD_SITE" \
    "DD_ENV=$DD_ENV" \
    "DD_SERVICE=$DD_SERVICE" \
    "DD_VERSION=$DD_VERSION" \
    "DD_LOGS_INJECTION=true" \
    "DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger" \
    "DD_TRACE_DEBUG=false" \
  -o none

echo ">> Tagging the Azure resource (Unified Service Tagging + LFO scope filter)..."
# env/service/version -> metrics correlation. REPRO_TAG -> lets the LFO log forwarder
# target ONLY this app via a tag filter, avoiding the rest of the shared subscription.
az resource tag \
  --tags "env=$DD_ENV" "service=$DD_SERVICE" "version=$DD_VERSION" "$REPRO_TAG_KEY=$REPRO_TAG_VALUE" \
  --name "$FUNCTION_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --resource-type "Microsoft.Web/sites" \
  -o none || echo "   (tagging skipped/failed - non-fatal)"

echo ""
echo "Provisioning complete."
echo "  Function App URL: https://$FUNCTION_APP.azurewebsites.net"
echo "  Next: ./02-deploy.sh"
