# Operations

Operations follow the **Command Pattern** for discrete, event-driven domain actions.

## Characteristics

| Aspect | Description |
|--------|-------------|
| Interface | Single `#call` method |
| State | Stateless - one-shot execution |
| Purpose | Domain actions triggered by events (webhooks, user actions, background jobs) |
| Results | Returns symbols or values (`:success`, `:skipped`, `:error`) |
| Reusability | Designed to be called from controllers, CLI, workers, or tests |

## Structure

```ruby
module Onetime
  module Operations
    class DoSomething
      def initialize(param:, context: {})
        @param = param
        @context = context
      end

      # Single entry point - executes and returns result
      def call
        # ... perform the operation
        :success
      end
    end
  end
end
```

## Usage

```ruby
# Instantiate with parameters, call once, discard
result = Onetime::Operations::DispatchNotification.new(
  data: notification_data,
  context: { source: 'webhook' }
).call

# Some operations provide a class-level convenience method
result = SomeOperation.call(param: value)
```

## When to Use Operations

- Processing webhook events
- Sending notifications
- Creating/updating domain entities as part of a workflow
- Actions that should be reusable across controllers, CLI, and background jobs

## Examples in Codebase

- `Onetime::Operations::DispatchNotification` - Dispatches notifications to multiple channels
- `Auth::Operations::CreateCustomer` - Creates customer records during signup
- `Auth::Operations::SyncSession` - Syncs Rodauth session with application session
- `Billing::Operations::ProcessWebhookEvent` - Routes Stripe webhook events to handlers

## Comparison with Other Patterns

| Aspect | Logic | Operations | Services |
|--------|-------|-----------|----------|
| Context | HTTP-bound (session, params) | Context-free | Context-free |
| Interface | `process`, `success_data` | Single `#call` | Multiple methods |
| State | Request-scoped | Stateless | Stateful |
| Lifecycle | Request-response | One-shot | Multi-phase |
| Primary use | API endpoints | Event handlers | CLI, admin tools |
| Results | JSON-ready data | Return symbols | Statistics, reports |

### Operations vs Logic

**Operations** are context-independent:
- Don't know about HTTP, sessions, or authentication
- Take simple constructor arguments (often with keyword args)
- Return simple result symbols (`:success`, `:skipped`, `:error`)
- Reusable from any context (controllers, CLI, background jobs)

**Logic** classes are HTTP request-bound:
- Receive authentication context and HTTP params
- Return data structures for JSON API responses
- Have form error handling for validation

## See Also

- `lib/onetime/logic/` - For HTTP request processing base classes
- `lib/onetime/services/` - For multi-phase administrative tools
- `apps/web/auth/operations/` - Auth-specific operations
- `apps/web/billing/operations/` - Billing-specific operations
