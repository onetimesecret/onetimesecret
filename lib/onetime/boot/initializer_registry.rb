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
            # Instantiate the initializer
            initializer = klass.new

            # Check for duplicate names
            if @initializers.any? { |i| i.name == klass.initializer_name }
              raise ArgumentError, "Initializer already registered: #{klass.initializer_name}"
            end

            @initializers << initializer

            # Map capabilities to their providing initializers
            Array(klass.provides).each do |capability|
              if @capability_map.key?(capability)
                existing = @capability_map[capability]
                raise ArgumentError,
                      "Capability '#{capability}' already provided by #{existing.name}"
              end
              @capability_map[capability] = initializer
            end
          end

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

            # Check if dependencies were satisfied
            if dependencies_failed?(initializer)
              initializer.skip!
              results[:skipped] << initializer
              log_initializer(prefix, initializer)
              next
            end

            # Log start
            log_initializer(prefix, initializer, before: true)

            # Execute
            begin
              initializer.run(@context)
              # Check if initializer failed (optional initializers don't raise)
              if initializer.failed?
                results[:failed] << initializer
                log_error(prefix, initializer, initializer.error)
              else
                results[:successful] << initializer
              end
            rescue StandardError => e
              results[:failed] << initializer
              log_error(prefix, initializer, e)
              raise unless initializer.optional
            end

            # Log completion
            log_initializer(prefix, initializer)
          end

          @total_elapsed_ms = ((Onetime.now_in_μs - @boot_start_time) / 1000.0).round(2)
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

        # Reset registry state (for testing)
        #
        # Clears all registrations and cached state
        def reset!
          @registered_classes = []
          @initializers       = []
          @capability_map     = {}
          @execution_order    = nil
          @context            = {}
          @total_elapsed_ms   = 0
          @boot_start_time    = nil
        end

        # TSort interface: iterate over all nodes
        def tsort_each_node(&)
          @initializers.each(&)
        end

        # TSort interface: iterate over dependencies of a node
        #
        # Maps capability dependencies to concrete initializers
        def tsort_each_child(initializer, &block)
          initializer.dependencies.each do |capability|
            provider = @capability_map[capability]
            if provider.nil?
              raise ArgumentError,
                    "Initializer '#{initializer.name}' depends on unknown capability '#{capability}'"
            end
            block.call(provider)
          end
        end

        private

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

        # Log initializer execution
        #
        # @param prefix [String] Step number prefix
        # @param initializer [Initializer]
        # @param before [Boolean] Whether this is before execution
        def log_initializer(prefix, initializer, before: false)
          if before
            Onetime.app_logger.debug "#{prefix} #{initializer.description}"
          else
            status = initializer.formatted_status
            Onetime.app_logger.debug "#{prefix} #{initializer.description} #{status}"
          end
        end

        # Log initialization error
        #
        # @param prefix [String] Step number prefix
        # @param initializer [Initializer]
        # @param error [Exception]
        def log_error(prefix, initializer, error)
          Onetime.app_logger.error "#{prefix} #{initializer.description} FAILED"
          Onetime.app_logger.error "  #{error.class}: #{error.message}"
          if Onetime.debug?
            error.backtrace.first(5).each do |line|
              Onetime.app_logger.error "    #{line}"
            end
          end
        end
      end
    end
  end
end
