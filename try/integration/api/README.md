# API Integration Tests

This directory contains integration tests for API endpoints, organized by API version/namespace.

## Directory Structure

```
try/integration/api/
├── v2/          # V2 API integration tests (public secrets API)
├── v3/          # V3 API integration tests (public secrets API with JSON types)
└── account/     # Account API integration tests (authenticated account/domain endpoints)
```

## Organization Guidelines

### Integration Tests (this directory)
- Test complete API request/response cycles
- Test API-specific behavior (transformations, response formats)
- Organized by API version/namespace

### Unit Tests (try/unit/logic/)
- Test individual logic classes
- Organized by domain (secrets, account, authentication), NOT by API version
- V2/V3/Account logic classes share business logic, only differ in serialization

## Example

**Integration test** (tests v3 API endpoint response format):
- `try/integration/api/v3/rest_transformations_try.rb`

**Unit test** (tests shared business logic):
- `try/unit/logic/secrets/reveal_secret_try.rb` (tests V2::Logic::Secrets::RevealSecret)
