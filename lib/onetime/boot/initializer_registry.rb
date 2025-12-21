# lib/onetime/boot/initializer_registry.rb
#
# frozen_string_literal: true

require 'tsort'
require_relative 'initializer'

module Onetime
  module Boot
    # Registry for boot initializers with dependency-based ordering
    #
    # Manages registration and execution of boot initializers using TSort
    # for automatic dependency resolution. Mirrors the pattern from
    # Application::Registry and SerializerRegistry.
    #
    # Features:
    # - Automatic dependency ordering via TSort
    # - Capability-based dependencies (depends_on/provides pattern)
    # - Progress tracking with detailed timing
    # - Support for optional vs required initializers
    # - Per-application initializer registration
    # - Parallel execution phases (future enhancement)
    #
    # @example Register core initializers
    #   InitializerRegistry.register(
    #     name: :config_load,
    #     description: 'Load configuration',
    #     provides: [:config]
    #   ) { |ctx| Onetime.load_config }
    #
    # @example Register with dependencies
    #   InitializerRegistry.register(
    #     name: :database_init,
    #     description: 'Initialize database',
    #     depends_on: [:config, :logging],
    #     provides: [:database]
    #   ) { |ctx| setup_database }
    #
    # @example Run all initializers
    #   InitializerRegistry.run_all
    #
    class InitializerRegistry
      extend TSort

      # Registry state (populated at boot time, then readonly)
      # rubocop:disable ThreadSafety/MutableClassInstanceVariable
      @registered_classes  = []  # Phase 1: Class discovery
      @initializers        = []  # Phase 2: Instantiated initializers
      @capability_map      = {}  # capability => initializer that provides it
      @execution_order     = nil # cached tsort result
      @context             = {}  # shared context across initializers
      @total_elapsed_ms    = 0
      @boot_start_time     = nil
      # rubocop:enable ThreadSafety/MutableClassInstanceVariable

      class << self
        attr_reader :initializers, :capability_map, :context, :total_elapsed_ms

        # Phase 1: Register initializer class (called by inherited hook)
        #
        # @param klass [Class] Initializer subclass
        # @return [void]
        def register_class(klass)
          @registered_classes << klass unless @registered_classes.include?(klass)
        end

        # Phase 2: Load all registered initializers
        #
        # Instantiates initializer classes and builds dependency graph.
        # Called once during boot after all classes are loaded.
        #
        # @return [void]
        def load_all
          @registered_classes.each do |klass|
            # Skip if already loaded (idempotent for test re-runs)
            next if @initializers.any? { |i| i.name == klass.initializer_name }

            # Instantiate the initializer
            initializer = klass.new

            @initializers << initializer

            # Map capabilities to their providing initializers
            Array(klass.provides).each do |capability|
              next if @capability_map.key?(capability) # Skip if already provided

              @capability_map[capability] = initializer
            end
          end

          # Validate fork-sensitive initializers
          validate_fork_sensitive_initializers!

          # Clear cached execution order
          @execution_order = nil
        end

        # Get initializers in dependency order
        #
        # Uses TSort to compute correct execution order based on
        # dependencies. Results are cached after first computation.
        #
        # @return [Array<Initializer>] Ordered list of initializers
        # @raise [TSort::Cyclic] If circular dependencies detected
        def execution_order
          @execution_order ||= tsort
        end

        # Run all registered initializers in dependency order
        #
        # Executes each initializer sequentially, tracking progress and
        # timing. Halts on first failure unless initializer is optional.
        #
        # @return [Hash] Results with timing and status
        # @raise [StandardError] If required initializer fails
        def run_all
          @boot_start_time = Onetime.now_in_μs
          @context         = {}
          results          = {
            successful: [],
            failed: [],
            skipped: [],
            total_elapsed_ms: 0,
          }

          ordered = execution_order
          total   = ordered.size

          ordered.each_with_index do |initializer, idx|
            step_number = idx + 1
            prefix      = "[#{step_number}/#{total}]"

            init_logger.debug "#{prefix} Starting #{initializer.name} (depends_on: #{initializer.dependencies.inspect}, provides: #{initializer.provides.inspect})"

            # Check if dependencies were satisfied
            if dependencies_failed?(initializer)
              initializer.skip!
              results[:skipped] << initializer
              init_logger.debug "#{prefix} Skipped #{initializer.name} - dependencies failed"
              log_initializer(prefix, initializer)
              next
            end

            # Check if initializer wants to skip itself (e.g., feature disabled)
            if initializer.should_skip?
              initializer.skip!
              results[:skipped] << initializer
              init_logger.debug "#{prefix} Skipped #{initializer.name} - should_skip? returned true"
              log_initializer(prefix, initializer)
              next
            end

            # Execute
            begin
              initializer.run(@context)
              # Check if initializer failed (optional initializers don't raise)
              if initializer.failed?
                results[:failed] << initializer
                log_error(prefix, initializer, initializer.error)
              else
                results[:successful] << initializer
                init_logger.debug "#{prefix} Completed #{initializer.name} in #{initializer.elapsed_ms}ms"
              end
            rescue StandardError => ex
              results[:failed] << initializer
              log_error(prefix, initializer, ex)
              raise unless initializer.optional
            end

            # Log completion
            log_initializer(prefix, initializer)
          end

          @total_elapsed_ms          = ((Onetime.now_in_μs - @boot_start_time) / 1000.0).round(2)
          results[:total_elapsed_ms] = @total_elapsed_ms

          results
        end

        # Check if this registry has completed initialization
        #
        # @return [Boolean]
        def initialized?
          !@boot_start_time.nil?
        end

        # Get health status across all initializers
        #
        # Healthy means no required initializers failed. Skipped and pending
        # initializers (from conditional execution) don't affect health.
        #
        # @return [Hash] Health check results
        def health_check
          {
            healthy: @initializers.reject(&:optional).none?(&:failed?),
            total: @initializers.size,
            completed: @initializers.count(&:completed?),
            failed: @initializers.count(&:failed?),
            skipped: @initializers.count(&:skipped?),
            pending: @initializers.count { |i| i.status == Initializer::STATUS_PENDING },
            total_elapsed_ms: @total_elapsed_ms,
          }
        end

        # Get fork-sensitive initializers
        #
        # Returns initializers that need cleanup before fork and reconnect after fork.
        #
        # @return [Array<Initializer>] Fork-sensitive initializers
        def fork_sensitive_initializers
          @initializers.select { |init| init.phase == :fork_sensitive }
        end

        # Cleanup all fork-sensitive initializers before fork
        #
        # Calls cleanup method on each fork-sensitive initializer. Methods are
        # guaranteed to exist by validate_fork_sensitive_initializers!.
        #
        # Error handling strategy:
        # - NoMethodError/NameError: Re-raise (programming errors, expose bugs)
        # - StandardError: Log and continue (operational errors, degraded mode)
        #
        # Individual initializers should handle their own specific errors
        # for better error messages.
        #
        # @return [void]
        def cleanup_before_fork
          fork_sensitive_initializers.each do |init|
            init.cleanup
          rescue NameError
            # Programming errors (includes NoMethodError) - re-raise to expose bugs
            raise
          rescue StandardError => ex
            # Operational errors - continue with degraded mode
            init_logger.warn "[before_fork] Error cleaning up #{init.name}: #{ex.message}"
          end
        end

        # Reconnect all fork-sensitive initializers after fork
        #
        # Calls reconnect method on each fork-sensitive initializer. Methods are
        # guaranteed to exist by validate_fork_sensitive_initializers!.
        #
        # Error handling strategy:
        # - NoMethodError/NameError: Re-raise (programming errors, expose bugs)
        # - StandardError: Log and continue (operational errors, degraded mode)
        #
        # Individual initializers should handle their own specific errors
        # for better error messages.
        #
        # @return [void]
        def reconnect_after_fork
          fork_sensitive_initializers.each do |init|
            init.reconnect
          rescue NameError
            # Programming errors (includes NoMethodError) - re-raise to expose bugs
            raise
          rescue StandardError => ex
            # Operational errors - continue with degraded mode
            init_logger.warn "[before_worker_boot] Error reconnecting #{init.name}: #{ex.message}"
          end
        end

        # Reset registry state (for testing)
        #
        # Clears instance state and cached execution data, but preserves class registrations.
        # Initializer classes are registered once via the inherited hook when first required.
        # After reset!, calling load_all will re-instantiate from the preserved class list.
        def reset!
          # Keep @registered_classes - these are static class references that don't change
          # Only clear instance state and execution data
          @initializers       = []
          @capability_map     = {}
          @execution_order    = nil
          @context            = {}
          @total_elapsed_ms   = 0
          @boot_start_time    = nil
        end

        # Full reset including registered classes - for test isolation only
        #
        # WARNING: Only use in tests. Clears all state including class registrations.
        # After calling this, initializer classes must be re-registered (typically
        # by re-requiring the files that define them).
        #
        # @return [void]
        def reset_all!
          @registered_classes = []
          reset!
        end

        # TSort interface: iterate over all nodes
        def tsort_each_node(&)
          @initializers.each(&)
        end

        # TSort interface: iterate over dependencies of a node
        #
        # Maps capability dependencies to concrete initializers
        def tsort_each_child(initializer)
          initializer.dependencies.each do |capability|
            provider = @capability_map[capability]
            if provider.nil?
              raise ArgumentError,
                "Initializer '#{initializer.name}' depends on unknown capability '#{capability}'"
            end
            yield(provider)
          end
        end

        private

        # Validate fork-sensitive initializers have required methods
        #
        # Ensures all :fork_sensitive initializers implement cleanup and reconnect methods.
        # Called during load_all to fail fast before Puma starts forking.
        #
        # @raise [OT::Problem] If fork-sensitive initializer missing required methods
        # @return [void]
        def validate_fork_sensitive_initializers!
          @initializers.each do |initializer|
            next unless initializer.phase == :fork_sensitive

            missing = []
            missing << 'cleanup' unless initializer.respond_to?(:cleanup)
            missing << 'reconnect' unless initializer.respond_to?(:reconnect)

            next if missing.empty?

            raise Onetime::Problem,
              "Fork-sensitive initializer '#{initializer.name}' must implement: #{missing.join(', ')}"
          end
        end

        # Check if any of this initializer's dependencies failed
        #
        # @param initializer [Initializer]
        # @return [Boolean]
        def dependencies_failed?(initializer)
          initializer.dependencies.any? do |capability|
            provider = @capability_map[capability]
            provider && (provider.failed? || provider.skipped?)
          end
        end

        # Get logger for boot progress
        #
        # Always uses stdlib Logger to $stderr for the entire boot process.
        # Never switches to SemanticLogger to avoid auto-configuration issues.
        #
        # @return [Logger]
        def init_logger
          @init_logger ||= begin
            logger           = Logger.new($stderr)
            # Check DEBUG_BOOT directly since SemanticLogger config hasn't run yet.
            # Fall back to WARN to match typical loggers.Boot config.
            logger.level     = ENV['DEBUG_BOOT'] ? Logger::DEBUG : Logger::WARN
            logger.formatter = proc do |_severity, _datetime, _progname, msg|
              "#{msg}\n"
            end
            logger
          end
        end

        # Log initializer execution
        #
        # @param prefix [String] Step number prefix
        # @param initializer [Initializer]
        def log_initializer(prefix, initializer)
          status = initializer.formatted_status
          init_logger.info "#{prefix} #{initializer.description} #{status}"
        end

        # Log initialization error
        #
        # @param prefix [String] Step number prefix
        # @param initializer [Initializer]
        # @param error [Exception]
        def log_error(prefix, initializer, error)
          init_logger.error "#{prefix} #{initializer.description} FAILED"
          init_logger.error "  #{error.class}: #{error.message}"
          return unless Onetime.debug?

          error.backtrace.first(5).each do |line|
            init_logger.error "    #{line}"
          end
        end
      end
    end
  end
end
