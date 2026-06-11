using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

// 1) Start the Datadog Serverless Compatibility Layer FIRST, before the host is built.
//    This boots the bundled mini-agent that ships APM traces + runtime/enhanced/custom
//    metrics to Datadog. It does NOT collect logs.
Datadog.Serverless.CompatibilityLayer.Start();

// 2) Build the Functions app. Application logs use the plain Microsoft.Extensions.Logging
//    ILogger<T> abstraction (see OrderFunction.cs) - there is NO logging code wired to
//    Datadog here.
//
//    Correlated log path (the fix) is now CONFIG-ONLY via Datadog Direct Log Submission:
//    setting DD_LOGS_DIRECT_SUBMISSION_INTEGRATIONS=ILogger makes the Datadog .NET tracer's
//    automatic instrumentation attach a logging provider that ships ILogger logs straight to
//    the Datadog intake over HTTPS (URL derived from DD_SITE), stamped with dd.trace_id /
//    dd.span_id (because DD_LOGS_INJECTION=true). No NuGet sink, no app code.
//
//    Forwarder path (the customer's scenario) stays intact: Application Insights keeps
//    feeding the Functions host -> FunctionAppLogs, which a diagnostic setting forwards to
//    Datadog (no trace correlation).
var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Build().Run();
