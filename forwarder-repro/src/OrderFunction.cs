using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace src;

public class OrderFunction
{
    private readonly ILogger<OrderFunction> _logger;

    public OrderFunction(ILogger<OrderFunction> logger)
    {
        _logger = logger;
    }

    // HTTP-triggered function used to exercise APM tracing + log/trace correlation.
    // Every log line emitted inside this invocation runs under an active trace, so with
    // DD_LOGS_INJECTION=true the tracer stamps the same dd.trace_id onto each record.
    // Whether that id survives the FunctionAppLogs -> forwarder path is what we observe.
    [Function("OrderFunction")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        var orderId = Guid.NewGuid().ToString("N")[..8];

        _logger.LogInformation("Received order request {OrderId}", orderId);

        try
        {
            await ProcessOrderAsync(orderId);
            _logger.LogInformation("Order {OrderId} processed successfully", orderId);
            return new OkObjectResult(new { orderId, status = "processed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process order {OrderId}", orderId);
            return new ObjectResult(new { orderId, status = "error" }) { StatusCode = 500 };
        }
    }

    private async Task ProcessOrderAsync(string orderId)
    {
        _logger.LogDebug("Validating order {OrderId}", orderId);
        await Task.Delay(50);

        _logger.LogInformation("Charging payment for order {OrderId}", orderId);
        await Task.Delay(75);

        // Randomly fail to produce error traces + (hopefully) correlated error logs.
        if (Random.Shared.Next(0, 5) == 0)
        {
            throw new InvalidOperationException($"Payment gateway timeout for order {orderId}");
        }

        _logger.LogWarning("Inventory running low while fulfilling order {OrderId}", orderId);
        await Task.Delay(40);
    }
}
