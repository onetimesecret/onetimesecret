# lib/onetime/boot/initializer.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    # Base class for boot initializers
    #
    # Each initializer is a class that inherits from this base class.
    # Auto-registers via inherited hook when class is defined.
    #
    # @example Simple initializer
    #   class ConfigLoad < Boot::Initializer
    #     @provides = [:config]
    #
    #     def execute(context)
    #       # Load configuration
    #     end
    #   end
    #
    # @example With dependencies
    #   class DatabaseInit < Boot::Initializer
    #     @depends_on = [:config, :logging]
    #     @provides = [:database]
    #     @optional = false
    #
    #     def execute(context)
    #       # Initialize database
    #     end
    #   end
    #
    class Initializer
      include Onetime::LoggerMethods

      attr_reader :status, :error, :elapsed_ms
      attr_accessor :application_class

      # Class instance variables for configuration
      class << self
        attr_accessor :depends_on, :provides, :optional, :phase

        # Get phase for this initializer (default: :preload)
        #
        # Valid phases:
        # - :preload (default) - Safe to run before fork
        # - :fork_sensitive - Needs cleanup before fork and reconnect after fork
        #
        # @return [Symbol] Phase (:preload or :fork_sensitive)
        def phase
          @phase || :preload
        end

        # Auto-register when subclass is defined (Phase 1: Discovery)
        #
        # Registration strategy (DI architecture):
        # - If thread-local registry is active: Register ONLY with instance (test isolation)
        # - Otherwise: Register with class-level registry (production behavior)
        #
        # This prevents test classes from polluting the class-level registry.
        def inherited(subclass)
          super

          # Check for thread-local instance registry (test mode)
          current_registry = InitializerRegistry.current
          if current_registry
            # Register ONLY with instance (test isolation - no class-level pollution)
            current_registry.register_class(subclass)
          else
            # Register with class-level registry (production mode)
            InitializerRegistry.register_class(subclass)
          end
        end

        # Generate name from class name
        # Billing::Initializers::StripeSetup -> :billing.stripe_setup
        def initializer_name
          @initializer_name ||= name.gsub('::', '.')
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
        end
      end

      # Execution status values
      STATUS_PENDING   = :pending
      STATUS_RUNNING   = :running
      STATUS_COMPLETED = :completed
      STATUS_FAILED    = :failed
      STATUS_SKIPPED   = :skipped

      def initialize
        @status      = STATUS_PENDING
        @error       = nil
        @elapsed_ms  = 0
        @start_time  = nil
      end

      # Execute this initializer
      #
      # @param context [Hash] Shared context for initializers to read/write
      # @return [Object] Result of the execute method
      # @raise [StandardError] If initializer fails and is not optional
      def run(context)
        @start_time = Onetime.now_in_μs
        @status     = STATUS_RUNNING

        result = execute(context)

        @elapsed_ms = ((Onetime.now_in_μs - @start_time) / 1000.0).round(2)
        @status     = STATUS_COMPLETED

        result
      rescue StandardError => ex
        @elapsed_ms = ((Onetime.now_in_μs - @start_time) / 1000.0).round(2)
        @error      = ex
        @status     = STATUS_FAILED

        raise unless self.class.optional
      end

      # Subclasses must implement this method
      #
      # @param context [Hash] Shared context across all initializers
      # @return [Object] Result of initialization
      def execute(context)
        raise NotImplementedError, "#{self.class.name} must implement #execute"
      end

      # Skip this initializer without executing
      #
      # Used when dependencies fail or when conditionally disabled
      def skip!
        @status = STATUS_SKIPPED
      end

      # Predicate to determine if this initializer should be skipped
      #
      # Subclasses can override this to conditionally skip execution based on
      # configuration or other runtime conditions. Called by the registry
      # before executing the initializer.
      #
      # @return [Boolean] true if this initializer should be skipped
      def should_skip?
        false
      end

      # Check if this initializer completed successfully
      #
      # @return [Boolean]
      def completed?
        @status == STATUS_COMPLETED
      end

      # Check if this initializer failed
      #
      # @return [Boolean]
      def failed?
        @status == STATUS_FAILED
      end

      # Check if this initializer was skipped
      #
      # @return [Boolean]
      def skipped?
        @status == STATUS_SKIPPED
      end

      # Check if this initializer is currently running
      #
      # @return [Boolean]
      def running?
        @status == STATUS_RUNNING
      end

      # Get formatted status for logging
      #
      # @return [String] Status with optional timing
      def formatted_status
        case @status
        when STATUS_COMPLETED
          elapsed_ms > 100 ? "✓ (#{elapsed_ms}ms)" : '✓'
        when STATUS_FAILED
          self.class.optional ? '✗ (optional)' : '✗ FAILED'
        when STATUS_SKIPPED
          '⊘ skipped'
        when STATUS_RUNNING
          '⋯ running'
        else
          '○ pending'
        end
      end

      # Get initializer name
      #
      # @return [Symbol] Name derived from class
      def name
        self.class.initializer_name
      end

      # Get human-readable description from name
      #
      # @return [String] Formatted name for logging
      def description
        name.to_s.split('.').last.split('_').map(&:capitalize).join(' ')
      end

      # Get dependencies from class
      #
      # @return [Array<Symbol>] Dependencies
      def dependencies
        Array(self.class.depends_on)
      end

      # Get provides from class
      #
      # @return [Array<Symbol>] Provided capabilities
      def provides
        Array(self.class.provides)
      end

      # Check if this is an optional initializer
      #
      # @return [Boolean]
      def optional
        self.class.optional || false
      end

      # Get phase for this initializer
      #
      # @return [Symbol] Phase (:preload or :fork_sensitive)
      def phase
        self.class.phase
      end

      # Get application name for logging
      #
      # @return [String] Application class name or 'core'
      def application_name
        @application_class ? @application_class.name : 'core'
      end
    end
  end
end
