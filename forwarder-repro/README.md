# Forwarder-only log↔trace correlation reproduction

Tests one specific question for the customer's setup:

> If a **.NET** app logs through a real logging library (`ILogger`) **with `DD_LOGS_INJECTION=true`**,
> but ships those logs to Datadog **only via the Azure forwarder** (LFO → `FunctionAppLogs`),
> while traces come from the **Serverless Compatibility Layer** — do the logs and traces correlate?

| Setting | Value |
| --- | --- |
| Hosting plan | **Dedicated (App Service) plan** |
| Operating system | **Linux** |
| .NET worker model | **Isolated Worker** (.NET 9) |
| Traces | Datadog **Serverless Compatibility Layer** (`Datadog.AzureFunctions`) |
| Application logs | **`ILogger`** → Application Insights / host → `FunctionAppLogs` → **LFO forwarder** |
| Direct/agentless log submission | **OFF** (no Serilog sink, no `DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS`) |
| `DD_LOGS_INJECTION` | **true** |

This is deliberately the **opposite** of the "fix" repo (which ships logs in-process). Here logs
travel only through the forwarder, so we can observe empirically whether the injected trace IDs
survive that path.

## What we expect to learn
1. Do the worker's **custom `ILogger` lines even appear in `FunctionAppLogs`** in the isolated
   model, or only host events like `Executed 'OrderFunction'`?
2. If they appear, does the injected `dd.trace_id` arrive in Datadog's **reserved attribute** so a
   trace links to its logs — or is it buried (no link) unless a **Trace ID Remapper** is added to
   the logs pipeline?

Expected outcome: **not linked** out of the box. The forwarder delivers Azure platform/management-
plane logs; the trace ID (if present at all) is not mapped to the reserved `dd.trace_id` attribute.

## Repo layout

```
src/                     .NET 9 isolated worker Function app
  Program.cs             CompatibilityLayer.Start() + App Insights (plain ILogger; no log shipping code)
  OrderFunction.cs       HTTP trigger that logs at multiple levels (+ random errors)
  host.json              App Insights sampling disabled; log levels set
infra/
  00-config.sh           Shared names + Datadog config (edit/override here)
  01-provision.sh        Linux Dedicated plan + Function App + DD settings (injection ON, direct submission OFF)
  02-deploy.sh           Publishes code (incl. bundled tracer) to Azure
  04-setup-lfo.sh        LFO forwarder steps (scoped by tag) + verify the auto-created diagnostic setting
```

## Prerequisites
- Azure CLI (`az login` to the target subscription)
- .NET 9 SDK, Azure Functions Core Tools v4
- Datadog API key + site (US1), and the **Datadog–Azure integration** installed

## Run it

```bash
export DD_API_KEY=<US1 key from the SAME org the forwarder targets>
export DD_SITE=datadoghq.com          # US1

cd infra
./01-provision.sh        # plan + function app + DD settings (DD_LOGS_INJECTION=true, NO direct submission)
./02-deploy.sh           # publish the app

# Stand up the forwarder (Datadog Automated Log Forwarding, US1). Prints the scoped,
# tag-filtered LFO deploy steps, then verifies the auto-created diagnostic setting.
./04-setup-lfo.sh

# generate traffic (~1 in 5 calls errors on purpose)
FUNC=$(source ./00-config.sh >/dev/null; echo $FUNCTION_APP)
for i in $(seq 1 20); do curl -s "https://$FUNC.azurewebsites.net/api/OrderFunction" >/dev/null; done
```

> **Cost:** by default this creates its own Dedicated **P1V3** plan (bills hourly). To avoid a
> second plan, reuse the existing repro's plan/RG before provisioning:
> `export RESOURCE_GROUP=dd-func-repro-rg APP_SERVICE_PLAN=dd-func-repro-plan`

## Verify in Datadog (US1)
1. **Traces** — APM → Trace Explorer, filter `service:azure-functions-fwd-repro`. (Expected: ✅)
2. **Forwarder logs** — Log Explorer, `source:azure.*` scoped to the function app. Check:
   - Are the application `ILogger` lines present, or only host/platform events?
   - Do any carry a usable `dd.trace_id`?
3. **Correlation** — open a trace → **Logs** tab. (Expected: **not linked**.)

## Key environment variables (set by `01-provision.sh`)

| Name | Purpose |
| --- | --- |
| `CORECLR_ENABLE_PROFILING=1` | Attach the .NET CLR profiler |
| `CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8}` | Datadog profiler GUID |
| `CORECLR_PROFILER_PATH=/home/site/wwwroot/datadog/linux-x64/Datadog.Trace.ClrProfiler.Native.so` | Linux native tracer |
| `DD_DOTNET_TRACER_HOME=/home/site/wwwroot/datadog` | Tracer home |
| `DD_API_KEY`, `DD_SITE` | Datadog intake |
| `DD_ENV`, `DD_SERVICE`, `DD_VERSION` | Unified Service Tagging |
| `DD_LOGS_INJECTION=true` | Stamp trace IDs onto log records (but logs still go via the forwarder) |

> **Not set on purpose:** `DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS` (that would bypass the
> forwarder and is the "fix" path, not what this repro tests).
>
> **Do not set** `DD_AGENT_HOST` or `DD_TRACE_AGENT_URL` — they break serverless mode.

## If you want to make forwarder logs correlate anyway
Add a **Trace ID Remapper** in the Datadog logs pipeline for `source:azure.*` that extracts the
embedded trace ID into the reserved `dd.trace_id` attribute — *and* confirm the `ILogger` lines
actually reach `FunctionAppLogs` with that ID. Otherwise, switch to in-process shipping (the fix).
