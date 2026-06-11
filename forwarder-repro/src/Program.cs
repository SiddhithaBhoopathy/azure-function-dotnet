using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

// 1) Start the Datadog Serverless Compatibility Layer FIRST, before the host is built.
//    Ships APM traces + runtime/enhanced/custom metrics to Datadog. It does NOT collect logs.
Datadog.Serverless.CompatibilityLayer.Start();

// 2) FORWARDER-ONLY logging reproduction.
//    Application logs are written through plain Microsoft.Extensions.Logging ILogger<T>
//    (see OrderFunction.cs). The ONLY way those logs reach Datadog is the Azure path:
//        ILogger -> Application Insights / Functions host -> FunctionAppLogs -> LFO forwarder
//    There is NO direct/agentless log submission and NO Serilog sink here on purpose.
//
//    DD_LOGS_INJECTION=true is set on the app (01-provision.sh), so the .NET tracer stamps
//    dd_trace_id/dd_span_id onto the log records. This repro exists to answer empirically:
//      (a) do the worker's custom ILogger lines even appear in FunctionAppLogs, and
//      (b) if so, do the injected trace IDs survive the forwarder and link to the
//          compat-layer traces? (Expected: not linked without a Trace ID Remapper.)
var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Build().Run();
