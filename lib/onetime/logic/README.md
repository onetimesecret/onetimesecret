# Logic

Logic classes handle **HTTP request processing** for API endpoints. They are the "extracted controller logic" pattern.

## Characteristics

| Aspect | Description |
|--------|-------------|
| Context | Request-bound (receives session, auth, params from HTTP request) |
| Interface | `process_params`, `raise_concerns`, `process`, `success_data` |
| Purpose | Parse input, validate, execute domain logic, return API response data |
| Location | `apps/api/*/logic/` directories (version-specific) |
| Base class | `Onetime::Logic::Base` |

## Structure

```ruby
module V2::Logic
  module Secrets
    class ConcealSecret < V2::Logic::Base
      attr_reader :secret_value, :metadata

      # Parse and extract values from HTTP params
      def process_params
        @secret_value = params['secret']
      end

      # Validate inputs, raise FormError on failure
      def raise_concerns
        raise_form_error 'No secret provided' if secret_value.empty?
      end

      # Execute domain logic
      def process
        @metadata = create_secret(secret_value)
      end

      # Return data for JSON response
      def success_data
        { success: true, record: metadata.safe_dump }
      end

      # Fields to include in validation error responses
      def form_fields
        { secret: secret_value }
      end
    end
  end
end
```

## Key Features

1. **Request Context**: Receives `strategy_result` (auth/session) and `params` from HTTP layer
2. **Form Errors**: `raise_form_error` includes `form_fields` for validation feedback
3. **Response Data**: `success_data` returns structures ready for JSON serialization
4. **Helpers**: Access to `sess`, `cust`, `locale`, organization context

## Comparison with Other Patterns

| Aspect | Logic | Services | Operations |
|--------|-------|----------|------------|
| HTTP context | Yes (session, params) | No | No |
| Primary use | API endpoints | CLI/admin tools | Event handlers |
| Error handling | FormError with fields | Exceptions | Return symbols |
| Response format | JSON-ready data | Reports/statistics | Result symbols |

## When to Use Logic

- Processing API endpoint requests
- Validating user input with form-style error feedback
- Operations that need session/authentication context
- Returning structured JSON responses

## See Also

- `lib/onetime/services/` - For context-independent administrative tools
- `lib/onetime/operations/` - For discrete, event-driven domain actions
- `apps/api/v2/logic/` - V2 API logic classes
