#!/usr/bin/env bash
# Set up Datadog Automated Log Forwarding (LFO) so the Function App's FunctionAppLogs are
# forwarded to Datadog (US1). This is the customer's log path for this reproduction.
#
# LFO is deployed from the Datadog UI (it embeds your org's API key) OR via the public ARM
# template. The control plane then AUTO-DISCOVERS resources and AUTO-CREATES the diagnostic
# settings -- you do NOT create them manually. This script does not deploy LFO for you
# (interactive, needs your Datadog API key + elevated Azure perms); it prints the exact,
# scoped steps and then verifies.
#
# IMPORTANT: this is a SHARED sandbox subscription with existing LFO control planes.
# Scope the forwarder with a TAG FILTER so it only touches this repro's resources.
#
# Usage: ./04-setup-lfo.sh         # prints steps + runs verification checks

cd "$(dirname "$0")"
source ./00-config.sh

cat <<EOF

=====================================================================
 Deploy Datadog Automated Log Forwarding (LFO) for the forwarder repro
=====================================================================

In your US1 Datadog org (the one whose DD_API_KEY you used for traces):

  1. Go to: Integrations > Azure > Configure Log Forwarding
  2. Choose "Deploy a new setup" (do NOT extend an existing shared control plane).
  3. Copy the generated command and paste it into Azure Cloud Shell (Bash), OR use
     the ARM template and set:
        - Region:                       $LOCATION
        - Subscriptions to Forward:     $(az account show --query id -o tsv 2>/dev/null)
        - Control Plane Subscription:   (same)
        - Resource Group Name:          dd-lfo-fwd-repro-cp   (a NEW, unused RG)
        - Datadog API key:              <your US1 API key>
        - Datadog Site:                 $DD_SITE
  4. CRITICAL - add a RESOURCE TAG FILTER so only this repro is forwarded:
        include tag:   $REPRO_TAG_KEY:$REPRO_TAG_VALUE
     This prevents the forwarder from auto-instrumenting the rest of this
     shared subscription.
  5. Confirm / Review + create.

The control plane will then discover "$FUNCTION_APP" (tagged $REPRO_TAG_KEY=$REPRO_TAG_VALUE),
create a diagnostic setting for FunctionAppLogs, and forward those logs to Datadog US1.

=====================================================================
 Verification
=====================================================================
EOF

FUNCTION_APP_ID="$(az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)"

if [[ -z "$FUNCTION_APP_ID" ]]; then
  echo "Function App '$FUNCTION_APP' not found yet. Run ./01-provision.sh first."
  exit 0
fi

echo ">> Confirming the repro tag is present on the Function App..."
az resource show --ids "$FUNCTION_APP_ID" --query "tags" -o json

echo ""
echo ">> Checking whether LFO has created a diagnostic setting on the Function App..."
echo "   (appears within a few minutes after the control plane runs discovery)"
az monitor diagnostic-settings list --resource "$FUNCTION_APP_ID" \
  --query "value[].{name:name, categories:logs[?enabled].category, dest:join(',', [storageAccountId, eventHubAuthorizationRuleId, workspaceId, marketplacePartnerId][?@])}" \
  -o table 2>/dev/null || echo "   (none yet)"

cat <<EOF

Next: generate traffic, then in Datadog:
  - APM > Traces (service:$DD_SERVICE): confirm traces from the compat layer. (Expected: yes.)
  - Log Explorer (source:azure.* scoped to the function app): are the application ILogger
    lines present, or only host/platform events? Do any carry a usable dd.trace_id?
  - Open a trace > Logs tab: are the forwarder logs linked? (Expected: NOT linked, unless a
    Trace ID Remapper is configured in the logs pipeline.)
EOF
