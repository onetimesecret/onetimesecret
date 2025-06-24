# lib/onetime/ready.rb

module Onetime
  # About System Readiness
  #
  # The system operates in three discrete states -- process start,
  # boot-in-progress, and fully operational -- where configuration
  # access doesn't require system initialization and readiness.
  #
  # Basic application functionality works immediately with static config;
  # enhanced functionality requires full boot completion.
  #
  #   @ready = nil          # Process started, boot not yet attempted
  #   OT.conf               # Static config (frozen, minimal defaults)
  #
  #   @ready = false        # Boot attempted, in-progress or failed
  #   OT.conf               # Static config, validated with defaults applied (frozen)
  #
  #   @ready = true         # All services started and healthy
  #   OT.conf               # ConfigProxy (static + dynamic)
  #
  # Configuration Implications
  #   - **No external dependencies** for basic startup (skip schema validation pre-boot)
  #   - **Pre-boot**: Minimal pipeline (file → ERB → YAML → hardcoded defaults → freeze)
  #   - **Full boot**: Complete pipeline (validation, init scripts, service integrations)
  #
  # Testing Implications
  #   - **Unit tests**: Work with static config, no boot mocking needed
  #   - **Integration tests**: Mock `OT.ready?` only when testing dynamic behavior
  #   - **Discrete functionality**: Operates independently of system state

  class << self
    # Returns true if the system has completed full initialization
    #
    # @return [Boolean] true when all services are started and verified healthy,
    #   false when boot is in progress, nil when boot hasn't been attempted
    #
    # USAGE:
    # - Use to guard enhanced functionality that requires full system state
    # - Do NOT use to gate basic configuration access (use OT.conf directly)
    # - In tests, mock this only when testing dynamic/enhanced behavior
    #
    # STATES:
    # - nil: Initial state, no boot attempted
    # - false: Boot in progress, services starting
    # - true: Fully operational, all services healthy
    def ready?
      !!@ready
    end

    # Returns true if the system is not fully ready
    #
    # @return [Boolean] true if system is in State 1 (nil) or State 2 (false)
    #
    # USAGE:
    # - Convenience method for readability
    # - Use to conditionally disable enhanced features during startup
    # - Prefer positive logic with ready? when possible
    def not_ready?
      !ready?
    end

    # Indicates that boot process has been initiated but not completed. It's
    # called at the beginning of the boot process and again if there are any
    # errors during initialization.
    #
    # Static config is available.
    #
    def not_ready!
      @ready = false
    end

    # Transitions system to State 3 (true) - fully operational
    # Should only be called after all services are verified healthy
    #
    # Signals that full ConfigProxy and all services are available.
    #
    # USAGE:
    # - Call only after complete_initialization! has finished successfully
    # - Do not call directly; use complete_initialization! instead
    #
    def mark_ready!
      @ready = true
    end

    # Completes full system initialization and transitions to ready state
    # Performs all necessary service startup and verification steps
    #
    # INITIALIZATION PIPELINE:
    # 1. Load plans (Plan.load_plans!)
    # 2. Initialize and verify all services (TODO: implement)
    # 3. Validate full system health
    # 4. Mark system as ready
    #
    # USAGE:
    # - Call this after static configuration is loaded
    # - Should be called exactly once during application startup
    # - Failure should leave system in not_ready state
    #
    # CONFIGURATION STRATEGY:
    # - Pre-boot: Minimal pipeline (file → ERB → YAML → defaults → freeze)
    # - Full boot: Complete pipeline (validation, init scripts, service integration)
    # - No external dependencies for basic startup functionality
    #
    # TESTING IMPLICATIONS:
    # - Unit tests work with static config, no mocking needed
    # - Integration tests mock ready? only for dynamic behavior testing
    # - Discrete functionality operates independently of readiness state
    def complete_initialization!
      # Load plans
      Plan.load_plans!

      # TODO: Add additional service initialization steps:
      # - Validate configuration completeness
      # - Start background services
      # - Verify external dependencies
      # - Run health checks
      # - Initialize logging subsystems
      # - Load dynamic configuration

      mark_ready!
    end
  end
end
