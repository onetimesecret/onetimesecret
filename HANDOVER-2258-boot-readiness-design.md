# Handover: Boot Readiness Redesign - Issue #2258

## Date: 2025-12-26

## Background

Issue #2258 started as a `RSpec::Core::ExampleGroup::WrongScopeError` fix but revealed deeper architectural problems. Analysis of 50 commits showed a "whack-a-mole" pattern where fixing one test broke others.

**Root Cause**: Shared mutable boot state (`Onetime.@ready`) leaks between tests. The tri-state design (`nil`/`true`/`false`) creates ambiguity:
- `nil` = boot not attempted
- `true` = booted successfully
- `false` = explicitly marked not-ready

After `reset_ready!` sets `@ready = nil`, `ready?` returns `false`, causing `StartupReadiness` middleware to return 503 for subsequent tests.

## Relevant Memories

- `.serena/memories/test-oscillation-root-cause-analysis.md` - Full analysis of commit patterns, state leaks, and whack-a-mole evidence

## Research Findings

### Patterns Evaluated

1. **Rails Boolean Flag**: Simple `@initialized = true/false`. No reset concept in production.

2. **Puma Lifecycle Hooks**: `on_booted`, `on_worker_boot`, `after_booted`. Fork-aware but web-specific.

3. **Kubernetes 3-Probe Model**: Industry standard separating Startup/Liveness/Readiness concerns.

### 3-Probe Model Recommendation

The 3-probe model maps well across all OTS runtime contexts:

| Context | Startup | Liveness | Readiness |
|---------|---------|----------|-----------|
| Web (Puma) | Initializers done? | Process responding? | Can handle HTTP? |
| RabbitMQ worker | Connected to broker? | Heartbeat OK? | Ready to consume? |
| Rufus scheduler | Jobs registered? | Thread alive? | Can schedule new? |
| Test runner | Config loaded? | N/A | Dependencies ready? |

## Proposed Design

### Immediate Fix (2-Boolean Approach)

Replace tri-state with explicit booleans for shared boot phase:

```ruby
module Onetime
  @booted = false        # Has boot! completed successfully?
  @boot_attempted = false # Has boot! been called?

  def self.boot!(mode = nil)
    return if @booted && testing?  # Idempotent in test mode
    raise OT::Problem, "Boot already completed" if @booted

    @boot_attempted = true
    # ... run initializers ...
    @booted = true
  end

  def self.ready?
    @booted == true
  end

  def self.boot_attempted?
    @boot_attempted == true
  end

  # For tests that need to re-test boot behavior
  def self.reset_boot_state!
    @booted = false
    @boot_attempted = false
  end

  # For tests that need ready state without full boot cycle
  def self.force_ready_for_testing!
    raise "Only in test mode" unless testing?
    @booted = true
    @boot_attempted = true
  end
end
```

### Long-Term Architecture

Layer context-specific readiness on top of shared boot state:

```ruby
# Shared: Did core initialization complete?
Onetime.ready?

# Context-specific: Am I ready for MY job?
RabbitMQ::Consumer.ready?
Scheduler.ready?
WebApp.ready?
```

Each runtime context defines what "ready" means for its purpose. The boot state answers "did the app initialize?" - runtime readiness is separate.

## Migration Path

1. Add new methods (`reset_boot_state!`, `force_ready_for_testing!`) alongside old ones
2. Update tests to use new methods
3. Deprecate `not_ready`/`reset_ready!`
4. Remove deprecated methods after all tests pass

## Current CI Status

- **Full Mode SQLite**: 15 failures in `rodauth_spec.rb` (503 from StartupReadiness)
- **Disabled Mode**: 20 failures (entitlement_test_spec.rb, default_workspace_creation_spec.rb)
- Simple Mode: Passing

## Files to Modify

- `lib/onetime/boot.rb` - Replace `@ready` with `@booted`/`@boot_attempted`
- `spec/integration/all/initializers/boot_part1_spec.rb` - Use `reset_boot_state!`
- `spec/integration/all/initializers/boot_part2_spec.rb` - Use `reset_boot_state!`
- `spec/integration/all/config/after_load_spec.rb` - Use new methods

## Key Insight

The Puma approach is web-specific and doesn't translate to RabbitMQ workers or schedulers. The 3-probe model is context-agnostic - each runtime defines readiness for its purpose. The shared boot state just answers "did core initialization complete?"
