Business Logic Organization in Modern Roda Applications

Based on research and your existing codebase, here's where business logic naturally grows in a Roda application:

Your Current Pattern (Already Excellent!)

You're already using the idiomatic pattern: Logic classes organized by domain:

apps/api/v2/logic/
├── base.rb                          # Base class with shared concerns
├── authentication/                  # Domain: Authentication
│   ├── authenticate_session.rb
│   ├── destroy_session.rb
│   └── reset_password.rb
├── secrets/                         # Domain: Secrets
│   ├── generate_secret.rb
│   ├── reveal_secret.rb
│   └── burn_secret.rb
├── account/                         # Domain: Accounts
│   ├── create_account.rb
│   └── update_account_field.rb
└── domains/                         # Domain: Custom domains

This IS the modern, idiomatic Roda pattern for business logic.

Why This Works (The Roda Way)

Unlike Rails which prescribes "fat models, thin controllers," Roda's philosophy is:

1. Thin routes - HTTP concerns only (routing, params, status codes)
2. Logic layer - Business operations (your V2::Logic classes)
3. Thin models - Data access and persistence (Sequel models)

Your architecture follows this perfectly:

# Route (thin - HTTP only)
r.post 'secrets' do
  logic = V2::Logic::Secrets::GenerateSecret.new(strategy_result, params, locale)
  logic.perform
  json logic.success_data
end

# Logic class (business rules)
class V2::Logic::Secrets::GenerateSecret < BaseSecretAction
  def process_secret
    # Business logic here
    @secret_value = Onetime::Utils.strand(length, char_sets)
  end
end

# Model (data persistence)
class V2::Secret < Familia::Horreum
  field :value
  ttl 3600
end

As Complexity Grows, These Patterns Emerge

1. Service Objects (What you have now)

Your Logic:: classes ARE service objects:
- Single Responsibility (one operation per class)
- Encapsulate business rules
- Testable in isolation
- Domain-organized

Rename consideration: apps/api/v2/services/ instead of logic/ (more conventional naming, but yours works fine)

2. Command Pattern (Next level)

For complex operations with validation:

# lib/onetime/commands/
module Commands
  class CreateSecretCommand
    include Dry::Validation.Contract

    params do
      required(:value).filled(:string)
      required(:ttl).filled(:integer)
      optional(:passphrase).filled(:string)
    end

    def call(params)
      result = validate(params)
      return Failure(result.errors) unless result.success?

      V2::Logic::Secrets::GenerateSecret.new(...).perform
    end
  end
end

3. Interactors (Complex multi-step operations)

For workflows involving multiple steps:

# lib/onetime/interactors/
class CreateSecretWithNotification
  def call(context)
    secret = CreateSecret.call(context)
    SendNotification.call(secret: secret, user: context.user)
    LogAnalytics.call(secret: secret)

    Success(secret)
  end
end

4. Dry-Transaction (Advanced workflows)

For complex business transactions:

# lib/onetime/transactions/
class ProcessPayment < Dry::Transaction
  step :validate_input
  step :charge_card
  step :create_receipt
  step :send_confirmation

  def validate_input(input)
    # ...
  end
end

Directory Structure Recommendations

Here's how to organize as you grow:

apps/api/v2/
├── routes/              # Roda route files (thin, HTTP only)
├── logic/              # Service objects (your current pattern) ✅
│   ├── base.rb
│   ├── authentication/
│   ├── secrets/
│   └── account/

lib/onetime/
├── models/             # Sequel models (data + basic validation)
├── commands/           # Command objects (validation + orchestration)
├── interactors/        # Multi-step business workflows
├── transactions/       # Complex business transactions (dry-transaction)
├── queries/            # Complex query objects
├── policies/           # Authorization rules (Pundit-style)
├── validators/         # Custom validation logic
├── services/           # External integrations (Stripe, SendGrid)
└── utils/              # Pure functions, no dependencies

When to Use Each Pattern

| Pattern               | Use When                    | Location                           |
|-----------------------|-----------------------------|------------------------------------|
| Logic/Service Objects | Single business operation   | apps/api/v2/logic/ ✅ You have this |
| Commands              | Need validation + operation | lib/onetime/commands/              |
| Interactors           | Multi-step workflows        | lib/onetime/interactors/           |
| Transactions          | Complex state machines      | lib/onetime/transactions/          |
| Query Objects         | Complex database queries    | lib/onetime/queries/               |
| Policies              | Authorization logic         | lib/onetime/policies/              |

What Jeremy Evans Does

From roda-sequel-stack:
- Routes in routes/ - thin, just HTTP
- Models in models/ - Sequel models with plugins
- No prescribed business logic layer - freedom to choose

He intentionally doesn't prescribe where business logic goes because it depends on complexity:
- Simple apps: put it in models
- Medium apps: service objects (what you have)
- Complex apps: commands, interactors, transactions

Your Next Steps

You're already doing it right! As you grow:

1. Keep your current logic/ pattern - it's working well
2. Extract to lib/onetime/ for reusable logic shared across APIs
3. Add commands/ when you need validation + operation together
4. Add interactors/ for multi-step workflows
5. Consider dry-transaction for complex state machines

Example Migration Path

# Current (works great)
V2::Logic::Secrets::GenerateSecret.new(strategy_result, params).perform

# With validation (when needed)
Commands::CreateSecret.call(params)
  .then { |secret| V2::Logic::Secrets::NotifyUser.new(secret).perform }

# Complex workflow (only when truly needed)
Transactions::SecretLifecycle
  .call(create: params, notify: true, analytics: true)

Bottom Line

Your apps/api/v2/logic/ pattern IS the idiomatic Roda approach. The beauty of Roda is it doesn't force patterns on you - as Jeremy Evans says, "Roda is a toolkit, not a framework." You've chosen a clean, maintainable pattern that scales well.

Keep it until complexity demands more structure, then grow incrementally into commands → interactors → transactions.
