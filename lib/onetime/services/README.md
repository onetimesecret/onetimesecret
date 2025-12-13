# Services

Services are **multi-phase administrative tools** for complex, stateful operations.

## Characteristics

| Aspect | Description |
|--------|-------------|
| Interface | Multiple public methods (`validate!`, `execute!`, `preview`, `report`) |
| State | Maintains internal state across method calls |
| Purpose | Administrative/maintenance utilities with lifecycle phases |
| Results | Track statistics, generate reports, support dry-run/preview |
| Usage | Primarily CLI/admin scripts, interactive workflows |

## Structure

```ruby
module Onetime
  module Services
    class SomeService
      attr_reader :log_entries, :statistics

      def initialize(param1, param2, options = {})
        @param1 = param1
        @param2 = param2
        @log_entries = []
        @statistics = {}
      end

      # Preview what will happen
      def summarize_changes
        # ... return human-readable summary
      end

      # Validate inputs before execution
      def validate!
        # ... raise on validation failure
        true
      end

      # Execute the operation
      def execute!
        # ... perform the work
        # ... track statistics
        true
      end

      # Generate audit report
      def generate_report
        # ... return formatted report
      end
    end
  end
end
```

## Usage

```ruby
# Services support a multi-phase workflow
service = Onetime::Services::ChangeEmail.new(old_email, new_email, realm)

# Preview changes before executing
puts service.summarize_changes

# Validate inputs
service.validate!

# Execute with confirmation
if user_confirmed?
  service.execute!
  service.save_report_to_db
end
```

## When to Use Services

- Administrative tasks run from CLI
- Operations requiring preview/dry-run capabilities
- Multi-step processes with validation and execution phases
- Tasks that need audit trails or reporting
- Data migrations or bulk operations

## Examples in Codebase

- `Onetime::Services::ChangeEmail` - Changes customer email with validation and audit trail
- `Onetime::Services::RedisKeyMigrator` - Migrates Redis keys between databases with statistics

## Comparison with Other Patterns

| Aspect | Logic | Operations | Services |
|--------|-------|-----------|----------|
| Context | HTTP-bound (session, params) | Context-free | Context-free |
| Interface | `process`, `success_data` | Single `#call` | Multiple methods |
| State | Request-scoped | Stateless | Stateful |
| Lifecycle | Request-response | One-shot | Multi-phase |
| Primary use | API endpoints | Event handlers | CLI, admin tools |
| Results | JSON-ready data | Return symbols | Statistics, reports |

### Logic vs Services

**Logic** classes are tightly coupled to the HTTP request lifecycle:
- Receive authentication context (`strategy_result`) and HTTP params
- Return data structures suitable for JSON API responses
- Have form error handling for validation feedback
- Located in `apps/api/v2/logic/`

**Services** are context-independent:
- Don't know about HTTP, sessions, or authentication
- Take simple constructor arguments
- Support preview/dry-run workflows
- Generate reports and audit trails
- Located in `lib/onetime/services/`

## See Also

- `lib/onetime/logic/` - For HTTP request processing base classes
- `lib/onetime/operations/` - For single-purpose command pattern actions
- `lib/onetime/cli/` - CLI commands that use these services
