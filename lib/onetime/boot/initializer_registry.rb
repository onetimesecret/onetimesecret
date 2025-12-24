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
      include TSort  # Instance-level TSort only

      # Pure DI architecture - no class-level registration state
      # Discovery happens via ObjectSpace in load_all

      # Instance-level state only
      attr_reader :initializers, :capability_map, :context, :total_elapsed_ms

      # Initialize a new registry instance (thread-safe, isolated)
      #
      # Each instance maintains its own registration state, eliminating
      # test pollution without requiring reset methods.
      #
      # @return [InitializerRegistry]
      def initialize
        @initializers        = []
        @capability_map      = {}
        @execution_order     = nil
        @context             = {}
        @total_elapsed_ms    = 0
        @boot_start_time     = nil
      end

      # Discover initializer classes via ObjectSpace with required filter
      #
      # Separates discovery from loading - returns classes without mutating state.
      # The filter is required to force intentionality about which classes to load.
      #
      # @yield [klass] Filter block receiving each candidate class
      # @yieldparam klass [Class] An Initializer subclass
      # @yieldreturn [Boolean] true to include, false to exclude
      # @return [Array<Class>] Matching initializer classes
      # @raise [ArgumentError] if no filter block provided
      #
      # @example Production - discover all production initializers
      #   classes = InitializerRegistry.discover { |k| k.initializer_name&.to_s&.start_with?('onetime.') }
      #
      # @example Test - discover only test initializers
      #   classes = InitializerRegistry.discover { |k| k.initializer_name&.to_s&.include?('test_fork') }
      #
      def self.discover(&)
        raise ArgumentError, 'filter block required' unless block_given?

        ObjectSpace.each_object(Class).select do |klass|
          klass < Onetime::Boot::Initializer &&
            klass != Onetime::Boot::Initializer &&
            yield(klass)
        end
      end

      # Get the thread-local active registry (for test isolation)
      #
      # @return [InitializerRegistry, nil]
      def self.current
        Thread.current[:initializer_registry]
      end

      # Set the thread-local active registry
      #
      # @param registry [InitializerRegistry, nil]
      # @return [InitializerRegistry, nil]
      def self.current=(registry)
        Thread.current[:initializer_registry] = registry
      end

      # Execute block with a specific registry as current
      #
      # @param registry [InitializerRegistry]
      # @yield Block to execute with registry as current
      # @return Result of block
      def self.with_registry(registry)
        raise ArgumentError, 'registry cannot be nil' if registry.nil?

        previous     = current
        self.current = registry
        yield registry
      ensure
        self.current = previous
      end

      class << self
        # Cleanup all fork-sensitive initializers before fork
        #
        # Pure delegation to boot_registry instance.
        #
        # @return [void]
        def cleanup_before_fork
          Onetime.boot_registry&.cleanup_before_fork
        end

        # Reconnect all fork-sensitive initializers after fork
        #
        # Pure delegation to boot_registry instance.
        #
        # @return [void]
        def reconnect_after_fork
          Onetime.boot_registry&.reconnect_after_fork
        end
      end

      # Load all initializer classes via ObjectSpace discovery
      #
      # Discovers initializers that match the production namespace filter.
      # For tests requiring explicit control, use load_only(classes) instead.
      #
      # @return [void]
      def load_all
        classes = self.class.discover { |k| k.initializer_name&.to_s&.start_with?('onetime.') }
        load_classes(classes)
      end

      # Load only the specified initializer classes (no discovery)
      #
      # Use this for tests where you need explicit control over which
      # classes are loaded, avoiding ObjectSpace discovery pollution.
      #
      # @param classes [Array<Class>] Initializer classes to load
      # @return [void]
      #
      # @example Test with explicit classes
      #   registry.load_only([TestInit1, TestInit2])
      #
      def load_only(classes)
        load_classes(classes)
      end

      private

      # Internal method to load classes into the registry
      #
      # Validates each class has an identifiable name (either explicit
      # @initializer_name or derivable from class name). This is the
      # single validation point for both discover and load_only paths.
      #
      # @param classes [Array<Class>] Initializer classes to load
      # @return [void]
      def load_classes(classes)
        classes.each do |klass|
          # Skip unidentifiable classes (anonymous without explicit name)
          next unless klass.initializer_name

          # Skip duplicates
          next if @initializers.any? { |i| i.name == klass.initializer_name }

          initializer = klass.new
          @initializers << initializer

          Array(klass.provides).each do |capability|
            next if @capability_map.key?(capability)

            @capability_map[capability] = initializer
          end
        end

        validate_fork_sensitive_initializers!
        @execution_order = nil
      end

      public

      # Get initializers in dependency order
      #
      # @return [Array<Initializer>]
      def execution_order
        @execution_order ||= tsort
      end

      # Run all registered initializers
      #
      # @return [Hash] Results with timing and status
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

          init_logger.debug "#{prefix} Starting #{initializer.name}"

          if dependencies_failed?(initializer)
            initializer.skip!
            results[:skipped] << initializer
            log_initializer(prefix, initializer)
            next
          end

          if initializer.should_skip?
            initializer.skip!
            results[:skipped] << initializer
            log_initializer(prefix, initializer)
            next
          end

          begin
            initializer.run(@context)
            if initializer.failed?
              results[:failed] << initializer
              log_error(prefix, initializer, initializer.error)
            else
              results[:successful] << initializer
            end
          rescue StandardError => ex
            results[:failed] << initializer
            log_error(prefix, initializer, ex)
            raise unless initializer.optional
          end

          log_initializer(prefix, initializer)
        end

        @total_elapsed_ms          = ((Onetime.now_in_μs - @boot_start_time) / 1000.0).round(2)
        results[:total_elapsed_ms] = @total_elapsed_ms

        results
      end

      # Check if this instance has completed initialization
      #
      # @return [Boolean]
      def initialized?
        !@boot_start_time.nil?
      end

      # Get health status
      #
      # @return [Hash]
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
      # @return [Array<Initializer>]
      def fork_sensitive_initializers
        @initializers.select { |init| init.phase == :fork_sensitive }
      end

      # Cleanup before fork
      #
      # @return [void]
      def cleanup_before_fork
        fork_sensitive_initializers.each do |init|
          init.cleanup
        rescue NameError
          raise
        rescue StandardError => ex
          init_logger.warn "[before_fork] Error cleaning up #{init.name}: #{ex.message}"
        end
      end

      # Reconnect after fork
      #
      # @return [void]
      def reconnect_after_fork
        fork_sensitive_initializers.each do |init|
          init.reconnect
        rescue NameError
          raise
        rescue StandardError => ex
          init_logger.warn "[before_worker_boot] Error reconnecting #{init.name}: #{ex.message}"
        end
      end

      # TSort instance interface
      def tsort_each_node(&)
        @initializers.each(&)
      end

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

      def dependencies_failed?(initializer)
        initializer.dependencies.any? do |capability|
          provider = @capability_map[capability]
          provider && (provider.failed? || provider.skipped?)
        end
      end

      def init_logger
        @init_logger ||= begin
          logger           = Logger.new($stderr)
          logger.level     = ENV['DEBUG_BOOT'] ? Logger::DEBUG : Logger::WARN
          logger.formatter = proc do |_severity, _datetime, _progname, msg|
            "#{msg}\n"
          end
          logger
        end
      end

      def log_initializer(prefix, initializer)
        status = initializer.formatted_status
        init_logger.info "#{prefix} #{initializer.description} #{status}"
      end

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
