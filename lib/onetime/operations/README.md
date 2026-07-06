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

## Placement: domain-owned (app-scoped) vs cross-cutting (central)

**Decision D3 (Colonel Admin Rebuild epic #3653).** Operations live in one of two
homes, chosen by ownership — not by which surface (CLI, admin API, worker) happens
to call them:

| Home | What lives here | Namespace | Examples |
|------|-----------------|-----------|----------|
| **App-scoped** `apps/web/<app>/operations/` | Ops owned by a bounded domain (auth, billing, domains). The domain's models, database, and invariants live in that app. | `Auth::Operations::*`, `Billing::Operations::*` | `Auth::Operations::CreateCustomer`, `Auth::Operations::SetCustomerVerification`, `Auth::Operations::DeleteCustomer`, `Auth::Operations::Customers::*` |
| **Central** `lib/onetime/operations/` | Genuinely cross-cutting ops with no single domain owner. | `Onetime::Operations::*` | `Onetime::Operations::DispatchNotification` |

**App-scoped is the incumbent home and the default.** `apps/web/auth/operations/`
already owns the customer/account domain (create, close, verify, delete). New
customer-admin verbs extracted for the colonel admin API + CLI therefore stay in
the auth app under `apps/web/auth/operations/customers/` (`Auth::Operations::Customers::{List, Show, SetRole, SetVerification, Purge, Doctor}`),
alongside — and reusing — the incumbent `SetCustomerVerification` and
`DeleteCustomer`. They are the *single implementation* of each verb; the colonel
Logic classes (`apps/api/colonel/logic/colonel/*`) and the `bin/ots customers *`
CLI commands are thin adapters over them.

Reserve `lib/onetime/operations/` (central) for verbs that are truly ownerless and
cross-cutting (e.g. a future `Sessions`, `Queues`, or `Banners` admin verb that no
single app owns). The test: *if a domain app already owns the model and its
invariants, the op belongs in that app.* When in doubt, prefer app-scoped — moving
an op central later is cheap; untangling a wrongly-central op's hidden domain
coupling is not.

> The epic plan's earlier "central `lib/onetime/operations`" phrasing for customer
> ops is superseded by this rule: customer ops are auth-domain-owned and stay
> app-scoped.

## See Also

- `lib/onetime/logic/` - For HTTP request processing base classes
- `lib/onetime/services/` - For multi-phase administrative tools
- `apps/web/auth/operations/` - Auth-specific operations (incumbent app-scoped home)
- `apps/web/auth/operations/customers/` - Customer admin verbs (List/Show/SetRole/SetVerification/Purge/Doctor)
- `apps/web/billing/operations/` - Billing-specific operations
