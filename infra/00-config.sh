#!/usr/bin/env bash
# Shared configuration for the Datadog + Azure Functions reproduction.
# Source this file from the other scripts: `source ./00-config.sh`
# Override any value by exporting it before running, e.g. `export LOCATION=westeurope`.

set -euo pipefail

# ---- Azure resource names (override as needed) -------------------------------
export LOCATION="${LOCATION:-eastus}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-dd-func-repro-rg}"
export APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-dd-func-repro-plan}"
# Dedicated/App Service plan SKU (P1v3 = Premium v3 dedicated). Use S1 for cheaper.
export PLAN_SKU="${PLAN_SKU:-P1V3}"
# Storage account name must be globally unique, 3-24 lowercase alphanumeric chars.
export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-ddfuncrepro$RANDOM}"
# Function app name must be globally unique (becomes <name>.azurewebsites.net).
export FUNCTION_APP="${FUNCTION_APP:-dd-func-repro-$RANDOM}"
export RUNTIME="${RUNTIME:-dotnet-isolated}"
export RUNTIME_VERSION="${RUNTIME_VERSION:-9}"
export FUNCTIONS_VERSION="${FUNCTIONS_VERSION:-4}"

# ---- Datadog configuration ---------------------------------------------------
# REQUIRED: export your real key before running, e.g. `export DD_API_KEY=xxxx`.
# Use a key from the SAME org that the log forwarder (LFO) targets, so traces and
# forwarded logs land together. This repo targets US1 (datadoghq.com).
export DD_API_KEY="${DD_API_KEY:-}"
export DD_SITE="${DD_SITE:-datadoghq.com}"
export DD_ENV="${DD_ENV:-sandbox}"
export DD_SERVICE="${DD_SERVICE:-azure-functions-repro}"
export DD_VERSION="${DD_VERSION:-1.0.0}"

# Dedicated tag used to scope the LFO log forwarder to ONLY this repro's resources,
# so it does not auto-instrument the rest of this shared sandbox subscription.
export REPRO_TAG_KEY="${REPRO_TAG_KEY:-dd-log-repro}"
export REPRO_TAG_VALUE="${REPRO_TAG_VALUE:-true}"

echo "Config loaded:"
echo "  RESOURCE_GROUP = $RESOURCE_GROUP"
echo "  LOCATION       = $LOCATION"
echo "  PLAN ($PLAN_SKU) = $APP_SERVICE_PLAN"
echo "  STORAGE        = $STORAGE_ACCOUNT"
echo "  FUNCTION_APP   = $FUNCTION_APP"
echo "  DD_SITE        = $DD_SITE"
