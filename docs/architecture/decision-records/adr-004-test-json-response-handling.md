---
id: 004
status: accepted
title: ADR-004: Test Helper for Wrapped JSON Responses
---

## Status
Accepted

## Date
2025-10-10

## Context

During PR #1798 review, automated tooling flagged the nested JSON parsing logic in `spec/integration/dual_auth_mode_spec.rb` as potentially indicating inconsistent API response formats. The test helper performs double JSON parsing for certain responses.

The issue: Some API endpoints return JSON-wrapped responses where the actual data is a JSON string within a JSON envelope:
```json
{
  "success": true,
  "data": "{\"key\":\"value\"}"
}
```

This occurs when:
- Controllers use generic response wrappers that JSON-encode already-encoded data
- Legacy endpoints maintain backwards compatibility with older client expectations
- Error responses need additional metadata beyond the core response

The decision point: Should we refactor the API to eliminate double-encoded responses or maintain the test helper pattern?

## Decision

**We will maintain the test helper pattern** that handles both standard and wrapped JSON responses.

The helper implementation:
```ruby
def json_response
  response = JSON.parse(last_response.body)
  # Handle wrapped responses: {"data": "{...}", "success": true}
  if response.is_a?(Hash) && response['data'].is_a?(String)
    JSON.parse(response['data'])
  else
    response
  end
end
```

This approach:
- Accepts the current API response patterns as they are
- Provides transparent handling in tests
- Avoids breaking changes to API responses

## Consequences

### Positive

- **No Breaking Changes**: Existing API clients continue to work without modification
- **Test Stability**: Tests handle all current response formats gracefully
- **Pragmatic Solution**: Addresses the testing need without major refactoring
- **Backwards Compatibility**: Can support both old and new response formats during transition

### Negative

- **API Inconsistency**: Perpetuates non-uniform response format across endpoints
- **Client Complexity**: API consumers must handle different response patterns
- **Performance Overhead**: Double JSON parsing has minor performance impact
- **Technical Debt**: Defers addressing root cause of inconsistent responses

### Neutral

- **Test Infrastructure Only**: Helper is isolated to test code, not production
- **Documentation Need**: Response format variations must be documented per endpoint
- **Migration Path**: Helper can facilitate gradual API response normalization

## Implementation Notes

### Current Usage (2025-10-10)
The helper is used in:
- `spec/integration/dual_auth_mode_spec.rb` - Auth endpoint testing
- `try/integration/authentication/` - Tryouts integration tests

Endpoints with wrapped responses:
- `/auth/login` - Returns wrapped success response
- `/auth/create-account` - Returns wrapped account data
- Various error responses with metadata

### Future API Normalization (2025-10-10)
When API v3 is developed, consider:
1. Standardizing on single JSON encoding for all responses (see also ADR-003)
2. Versioning headers to indicate response format

### Testing Best Practices (2025-10-10)
Until API responses are normalized:
1. Use the `json_response` helper consistently in integration tests
2. Document which endpoints return wrapped responses
3. Add explicit tests for both response formats where applicable
4. Consider adding response format validation to API documentation
