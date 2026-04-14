# Observability in Nosia

Nosia provides comprehensive observability through structured logging, metrics, and tracing to monitor system health, performance, and behavior.

## Logging

### Configuration

**Production** (`config/environments/production.rb`):
```ruby
config.logger = ActiveSupport::Logger.new(STDOUT)
  .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
  .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
config.log_tags = [ :request_id ]
```

**Development**: Uses default Rails logging with verbose query and job logs enabled.

**Test**: Minimal logging to avoid test output pollution.

### Log Levels

- **INFO**: General system operation (job start/end, embedding generation)
- **ERROR**: Exception handling and recovery
- **DEBUG**: Detailed debugging (not enabled by default)

### Key Logging Points

#### Job Execution
- `ChatResponseJob`: Start, completion, and error logging with request details
- Background jobs: Progress and error handling

#### Model Operations
- `Chunk::Vectorizable`: Embedding generation lifecycle
- `McpServer`: Connection status, tool execution, errors
- `Chat::ContextRelevance`/`AnswerRelevance`: Guard model errors

#### Real-time Updates
- `Message`: Broadcast decisions and streaming updates

### Log Format

Structured logs with:
- Timestamp
- Severity level
- Request ID (in production)
- Context-specific tags
- Error backtraces (when applicable)

## Metrics

### Database Metrics

**ActiveRecord Instrumentation**:
- Query execution time
- Query count per request
- Cache hit/miss rates

**Solid Queue Metrics**:
- Job queue lengths
- Job execution time
- Job failure rates

### Performance Monitoring

**Key Performance Indicators**:
- Chat response time (end-to-end)
- Embedding generation latency
- Vector similarity search duration
- MCP tool execution time

## Tracing

### Request Tracing

**Request ID**: Automatically assigned and logged for correlation across services.

**Job Tracing**: ActiveJob tags jobs with execution context for end-to-end tracing.

### Error Tracing

**Exception Backtraces**: Full stack traces logged for all unhandled exceptions.

**Job Failures**: Solid Queue captures and stores failed job executions with error details.

## Monitoring Endpoints

### Health Checks

**`/up`**: Standard Rails health check endpoint
- Returns 200 if system is operational
- Used by load balancers and orchestration systems

### Job Monitoring

**Mission Control Jobs** (`/jobs`):
- Real-time job queue visualization
- Job status and execution history
- Failure analysis and retry management

## Alerting

### Critical Alerts

1. **Job Failures**: Consecutive failures in `ChatResponseJob` or document processing
2. **Embedding Generation Errors**: Failed embedding generation affecting RAG quality
3. **MCP Connection Issues**: MCP server disconnections or authentication failures
4. **Database Performance**: Slow queries or connection pool exhaustion

### Warning Alerts

1. **High Latency**: Chat response times exceeding thresholds
2. **Queue Backlog**: Growing background job queues
3. **Error Rates**: Increased error rates in API endpoints

## Best Practices

### Log Hygiene

- Avoid logging sensitive data (API keys, user content)
- Use structured logging for easier parsing
- Include context for correlation (request IDs, job IDs)
- Log at appropriate severity levels

### Metrics Collection

- Instrument key user journeys (document upload → chat completion)
- Track business metrics (chunks created, searches performed)
- Monitor resource utilization (memory, CPU, database connections)

### Incident Response

1. **Detection**: Alerts trigger from monitoring systems
2. **Diagnosis**: Use logs and traces to identify root cause
3. **Mitigation**: Apply fixes or roll back changes
4. **Resolution**: Verify system recovery
5. **Postmortem**: Document incident and preventive measures

## Development Observability

### Local Development

- **Log files**: `log/development.log` for full application logs
- **Console**: `bin/rails console` for interactive debugging
- **Job monitoring**: `bin/rails solid_queue:status` for queue status

### Testing

- **Test logs**: Minimal output to keep test runs clean
- **Performance tests**: Measure and assert response times
- **Integration tests**: Verify logging behavior

## Production Considerations

### Log Rotation

Configure log rotation for production deployments:
- Rotate logs daily or at size thresholds
- Compress and archive old logs
- Set appropriate retention periods

### Security

- Restrict access to logs and monitoring endpoints
- Encrypt sensitive data in logs
- Audit log access and modifications

### Scaling

- Centralize logs from multiple instances
- Aggregate metrics across pods/containers
- Maintain trace continuity in distributed environments
