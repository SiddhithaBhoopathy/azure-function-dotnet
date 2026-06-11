#!/usr/bin/env bash
# Publishes the function app code (including the bundled Datadog tracer under
# wwwroot/datadog/) to Azure.
#
# Usage: ./02-deploy.sh

cd "$(dirname "$0")"
source ./00-config.sh

SRC_DIR="../src"

echo ">> Publishing $FUNCTION_APP from $SRC_DIR ..."
# func publish runs `dotnet publish` and zip-deploys the output. The Datadog native
# .so files in the publish output land at /home/site/wwwroot/datadog/linux-x64/...,
# matching CORECLR_PROFILER_PATH set during provisioning.
( cd "$SRC_DIR" && func azure functionapp publish "$FUNCTION_APP" --dotnet-isolated )

echo ""
echo "Deploy complete. Generate traffic with:"
echo "  curl https://$FUNCTION_APP.azurewebsites.net/api/OrderFunction"
