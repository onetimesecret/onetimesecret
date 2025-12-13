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

## See Also

- `lib/onetime/services/` - For multi-phase administrative tools
- `apps/web/auth/operations/` - Auth-specific operations
- `apps/web/billing/operations/` - Billing-specific operations
