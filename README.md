# Datadog + Azure Functions (.NET) — correlated traces & logs

A working example that gets **APM traces and correlated application logs** from a C# Azure
Functions app into Datadog, for this configuration:

| Setting | Value |
| --- | --- |
| Hosting plan | **Dedicated (App Service) plan** |
| Operating system | **Linux** |
| .NET worker model | **Isolated Worker** (.NET 9) |
| Observability | **Datadog** (APM traces, metrics, application logs) |

Because this is **Linux + Dedicated + Isolated**, the correct Datadog install method is the
**Serverless Compatibility Layer** (`Datadog.AzureFunctions` NuGet package) — *not* the Windows
Azure App Service site extension.

## How it works

The Serverless Compatibility Layer ships **traces + metrics** directly from the worker. It does
**not** collect logs. To get **application logs that correlate with those traces**, this example
uses Datadog **Direct Log Submission** (agentless, in-process):

- `DD_LOGS_INJECTION=true` — the .NET tracer stamps `dd.trace_id` / `dd.span_id` onto each log record.
- `DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger` — the tracer's automatic instrumentation ships
  `ILogger` logs straight to the Datadog logs intake over HTTPS (URL derived from `DD_SITE`).


## Repo layout

```
src/                     .NET 9 isolated worker Function app
  Program.cs             CompatibilityLayer.Start() + App Insights (plain ILogger; no log code)
  OrderFunction.cs       HTTP trigger that logs at multiple levels (+ random errors)
  host.json              App Insights sampling disabled; log levels set
infra/
  00-config.sh           Shared names + Datadog config (edit/override here)
  01-provision.sh        Linux Dedicated plan + Function App + Datadog app settings
  02-deploy.sh           Publishes code (incl. bundled tracer) to Azure
```

## Prerequisites

- Azure CLI (`az login` to the target subscription)
- .NET 9 SDK, Azure Functions Core Tools v4
- Datadog API key + site

## Deploy

```bash
export DD_API_KEY=<your Datadog API key>
export DD_SITE=datadoghq.com          # US1 (change for your site)

cd infra
./01-provision.sh        # Linux Dedicated plan + function app + Datadog app settings
./02-deploy.sh           # publish the app

# generate traffic (~1 in 5 calls errors on purpose)
FUNC=$(source ./00-config.sh >/dev/null; echo $FUNCTION_APP)
for i in $(seq 1 20); do curl -s "https://$FUNC.azurewebsites.net/api/OrderFunction" >/dev/null; done
```

Then in Datadog: open a trace (`service:azure-functions-repro`) → the **Logs** tab shows the
linked application log lines, each carrying `dd.trace_id`. ✅

## Key environment variables (set by `01-provision.sh`)

| Name | Purpose |
| --- | --- |
| `CORECLR_ENABLE_PROFILING=1` | Attach the .NET CLR profiler |
| `CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8}` | Datadog profiler GUID |
| `CORECLR_PROFILER_PATH=/home/site/wwwroot/datadog/linux-x64/Datadog.Trace.ClrProfiler.Native.so` | Linux native tracer |
| `DD_DOTNET_TRACER_HOME=/home/site/wwwroot/datadog` | Tracer home |
| `DD_API_KEY`, `DD_SITE` | Datadog intake |
| `DD_ENV`, `DD_SERVICE`, `DD_VERSION` | Unified Service Tagging |
| `DD_LOGS_INJECTION=true` | Inject `dd.trace_id` / `dd.span_id` into logs (correlation) |
| `DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger` | Ship `ILogger` logs straight to the Datadog intake over HTTPS (URL from `DD_SITE`) |

> **Do not set** `DD_AGENT_HOST` or `DD_TRACE_AGENT_URL` — they break serverless mode.

## Verify

1. **Traces** — Datadog → APM → Trace Explorer, filter `service:azure-functions-repro`.
2. **Correlated logs** — Log Explorer, `source:csharp service:azure-functions-repro`.
   Open a log → it shows a linked trace; open a trace → the **Logs** tab shows the log lines.
   Confirm `dd.trace_id` is present on the log.

## Troubleshooting

- No traces: confirm the `CORECLR_*` vars and that `datadog/linux-x64/*.so` exists under
  `wwwroot` (check via Kudu). Set `DD_TRACE_DEBUG=true` and redeploy.
- Logs not correlated: ensure `DD_LOGS_INJECTION=true` **and** `DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger`
  are set on the app. (Direct submission relies on the CLR profiler, so the `CORECLR_*` vars must be working too.)
- No application logs in Datadog at all: confirm the worker's `ILogger` calls run under the
  profiler; set `DD_TRACE_DEBUG=true` and check the Datadog tracer logs.
- Intake debug: set `DD_LOG_LEVEL=debug`.

## References

- [Azure Functions serverless setup](https://docs.datadoghq.com/serverless/azure_functions/)
- [C# log collection (agentless / Direct Log Submission)](https://docs.datadoghq.com/logs/log_collection/csharp/)
- [Correlating .NET logs and traces](https://docs.datadoghq.com/tracing/other_telemetry/connect_logs_and_traces/dotnet/)
