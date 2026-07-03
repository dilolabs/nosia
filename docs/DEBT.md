# Technical Debt Register

This document tracks known technical debt in the Nosia codebase, including the nature of the debt, its impact, and plans for resolution.

## Technical Debt Categories

### 1. Testing Debt

**Issue**: Insufficient test coverage, especially for integration and system tests

**Impact**: 
- Higher risk of regressions
- Slower development velocity
- Harder to refactor confidently

**Location**: 
- Missing integration tests for key workflows
- Limited system test coverage
- Some models lack unit tests

**Resolution Plan**:
- **Short-term**: Add unit tests for critical models (Chat, Chunk, McpServer)
- **Medium-term**: Implement integration tests for RAG pipeline
- **Long-term**: Build comprehensive system test suite
- **Target**: 80%+ test coverage

**Priority**: High

### 2. Error Handling in MCP Integration

**Issue**: Basic error handling in MCP tool execution and connection management

**Impact**:
- MCP failures may not be gracefully handled
- Limited retry logic for transient failures
- Error messages could be more informative

**Location**:
- `app/models/mcp_server.rb` (tool execution)
- `app/models/chat/model_context_protocol.rb`
- MCP-related controllers

**Resolution Plan**:
- Add comprehensive error handling with retry logic
- Implement circuit breakers for MCP connections
- Improve error messages and logging
- Add connection health monitoring

**Priority**: Medium

### 3. Guard Model Configuration

**Issue**: Guard models (context/answer relevance) have basic implementation

**Impact**:
- May not catch all irrelevant contexts or answers
- Limited configurability
- Basic prompt templates

**Location**:
- `app/models/chat/context_relevance.rb`
- `app/models/chat/answer_relevance.rb`
- `config/prompts.yml` (guard prompts)

**Resolution Plan**:
- Enhance guard model prompts
- Add configuration options
- Implement more sophisticated validation logic
- Add performance metrics and tuning

**Priority**: Medium

### 4. Document Format Support

**Issue**: Limited document format support beyond PDF and text

**Impact**:
- Users need to convert documents to supported formats
- Missing common formats (DOCX, XLSX, PPTX)
- Docling integration is optional

**Location**:
- `app/models/document/parsable.rb`
- Document processing pipeline

**Resolution Plan**:
- Add native support for DOCX, XLSX, PPTX
- Improve Docling integration
- Add fallback parsers for common formats
- Implement better error handling for unsupported formats

**Priority**: Medium

### 5. Mobile UI Responsiveness

**Issue**: Web UI has limited mobile responsiveness

**Impact**:
- Poor user experience on mobile devices
- Limited accessibility
- May deter mobile users

**Location**:
- CSS stylesheets
- View templates
- JavaScript controllers

**Resolution Plan**:
- Implement responsive design patterns
- Test on various mobile devices
- Improve touch targets and navigation
- Add mobile-specific UI optimizations

**Priority**: Medium

### 6. API Rate Limiting

**Issue**: No rate limiting on API endpoints

**Impact**:
- Potential for API abuse
- Resource exhaustion risks
- No protection against DDoS

**Location**:
- API controllers
- Authentication middleware

**Resolution Plan**:
- Implement Rack::Attack or similar
- Add rate limiting configuration
- Implement API key rotation
- Add abuse detection

**Priority**: High (for production)

### 7. Performance Optimization

**Issue**: Some performance optimizations not yet implemented

**Impact**:
- Slower response times under load
- Higher resource usage
- Limited scalability

**Location**:
- Vector search queries
- Document processing jobs
- API response generation

**Resolution Plan**:
- Add query optimization
- Implement caching strategies
- Profile and optimize slow endpoints
- Add database indexing where needed

**Priority**: Medium

### 8. Monitoring and Observability

**Issue**: Basic monitoring and observability features

**Impact**:
- Limited visibility into system health
- Harder to debug production issues
- No proactive alerting

**Location**:
- Logging configuration
- Metrics collection
- Monitoring endpoints

**Resolution Plan**:
- Enhance structured logging
- Add performance metrics
- Implement health checks
- Set up alerting

**Priority**: Medium

### 9. Internationalization (i18n)

**Issue**: Limited internationalization support

**Impact**:
- English-only interface
- Limited global accessibility
- Harder to localize

**Location**:
- View templates
- Error messages
- UI text

**Resolution Plan**:
- Implement Rails i18n
- Extract strings for translation
- Add locale switching
- Support RTL languages

**Priority**: Low

### 10. Documentation Gaps

**Issue**: Some areas lack comprehensive documentation

**Impact**:
- Harder for new contributors
- Users may struggle with advanced features
- Knowledge silos

**Location**:
- MCP integration guides
- Advanced configuration
- Troubleshooting guides

**Resolution Plan**:
- Expand user documentation
- Add more examples and tutorials
- Improve API documentation
- Create contributor guides

**Priority**: Medium

## Technical Debt Tracking

### Current Debt Metrics

| Category | Count | Estimated Effort (days) |
|----------|-------|------------------------|
| Testing | 5+ | 10-15 |
| Error Handling | 3+ | 5-8 |
| Performance | 4+ | 8-12 |
| UI/UX | 3+ | 6-10 |
| Security | 2+ | 4-6 |
| Documentation | 3+ | 5-8 |

**Total Estimated Debt**: ~40-60 days

### Debt Reduction Plan

#### Phase 1: Critical Fixes (Next 3 Months)
1. **Add API rate limiting** - Protect production systems
2. **Improve testing** - Reduce regression risk
3. **Enhance error handling** - Improve reliability
4. **Add basic monitoring** - Better observability

#### Phase 2: Quality Improvements (Next 6 Months)
1. **Expand document format support** - Better user experience
2. **Improve guard models** - Better response quality
3. **Optimize performance** - Better scalability
4. **Enhance mobile UI** - Better accessibility

#### Phase 3: Long-term Enhancements (Future)
1. **Add internationalization** - Global accessibility
2. **Expand documentation** - Better onboarding
3. **Implement advanced features** - Competitive advantage

## Debt Management Process

### Identifying Debt
1. Code reviews flag potential debt
2. Bug reports indicate quality issues
3. Performance profiling reveals bottlenecks
4. User feedback highlights pain points
5. Regular architecture reviews

### Tracking Debt
1. Document in this file
2. Create GitHub issues with `debt` label
3. Add TODO comments in code where appropriate
4. Track in project management system

### Prioritizing Debt
1. **Impact**: How severely does it affect users?
2. **Risk**: What's the risk of not addressing it?
3. **Cost**: How much effort to resolve?
4. **Value**: What benefits does resolution provide?

### Resolving Debt
1. **Plan**: Break down into manageable tasks
2. **Schedule**: Allocate time in development cycles
3. **Implement**: Write code and tests
4. **Review**: Ensure quality and completeness
5. **Document**: Update this file and remove resolved items

## Debt Prevention Strategies

### Code Quality
- Maintain high test coverage
- Follow Rails conventions
- Use consistent patterns
- Write clean, maintainable code

### Development Process
- Regular code reviews
- Pair programming for complex features
- Architecture design sessions
- Technical spike for new technologies

### Documentation
- Document decisions in DECISIONS.md
- Keep architecture docs updated
- Write comprehensive commit messages
- Maintain up-to-date README files

### Continuous Improvement
- Regular refactoring sessions
- Performance tuning
- Security audits
- Dependency updates

## Debt Visualization

```
Technical Debt Breakdown by Category
┌─────────────────────────────────┐
│ Testing          ████████████████ 35% │
│ Performance      ██████████████    30% │
│ Error Handling   ██████████        20% │
│ Documentation    ██████            15% │
└─────────────────────────────────┘
```

## Resolved Debt

### [2025-11-15] Basic MCP Integration
**Resolution**: Implemented core MCP functionality with RubyLLM
**Impact**: Enabled tool integration and extended AI capabilities

### [2025-10-30] Multi-tenancy Implementation
**Resolution**: Implemented ActsAsTenant for account isolation
**Impact**: Secure data separation between accounts

### [2025-10-15] Vector Search Implementation
**Resolution**: Implemented pgvector for efficient similarity search
**Impact**: Fast and accurate document retrieval for RAG

## Debt Review Schedule

- **Monthly**: Review and prioritize technical debt
- **Quarterly**: Assess debt reduction progress
- **Annually**: Major debt cleanup initiatives

This document will be updated regularly as technical debt is identified, prioritized, and resolved.