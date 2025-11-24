# lib/onetime/boot/initializer.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    # Initializer represents a single initialization step in the boot sequence
    #
    # Each initializer can declare dependencies on other initializers and
    # capabilities it provides. The registry uses these declarations to
    # compute the correct execution order via topological sort.
    #
    # @example Simple initializer
    #   Initializer.new(
    #     name: :logging_setup,
    #     description: 'Configure logging system',
    #     depends_on: [:config]
    #   ) do |context|
    #     # Setup code here
    #   end
    #
    # @example With provides declaration
    #   Initializer.new(
    #     name: :database_init,
    #     description: 'Initialize database connections',
    #     depends_on: [:config, :logging],
    #     provides: [:database]
    #   ) do |context|
    #     # Setup code here
    #   end
    #
    class Initializer
      attr_reader :name, :description, :dependencies, :provides, :optional
      attr_accessor :status, :error, :elapsed_ms, :application_class

      # Execution status values
      STATUS_PENDING   = :pending
      STATUS_RUNNING   = :running
      STATUS_COMPLETED = :completed
      STATUS_FAILED    = :failed
      STATUS_SKIPPED   = :skipped

      # Initialize a new boot step
      #
      # @param name [Symbol] Unique identifier for this initializer
      # @param description [String] Human-readable description (optional, defaults to name)
      # @param depends_on [Array<Symbol>] Capabilities this initializer requires
      # @param provides [Array<Symbol>] Capabilities this initializer provides
      # @param optional [Boolean] Whether failure should halt boot sequence
      # @param application [Class] Application class that registered this initializer
      # @yield [context] Block to execute for initialization
      # @yieldparam context [Hash] Shared context across all initializers
      def initialize(name:, description: nil, depends_on: [], provides: [], optional: false, application: nil, &block)
        @name               = name
        @description        = description || name.to_s.split('_').map(&:capitalize).join(' ')
        @dependencies       = Array(depends_on).freeze
        @provides           = Array(provides).freeze
        @optional           = optional
        @application_class  = application
        @block              = block
        @status             = STATUS_PENDING
        @error              = nil
        @elapsed_ms         = 0
        @start_time         = nil
      end

      # Execute this initializer
      #
      # @param context [Hash] Shared context for initializers to read/write
      # @return [Object] Result of the block execution
      # @raise [StandardError] If initializer fails and is not optional
      def run(context)
        @start_time = Onetime.now_in_μs
        @status     = STATUS_RUNNING

        result = @block.call(context)

        @elapsed_ms = ((Onetime.now_in_μs - @start_time) / 1000.0).round(2)
        @status     = STATUS_COMPLETED

        result
      rescue StandardError => e
        @elapsed_ms = ((Onetime.now_in_μs - @start_time) / 1000.0).round(2)
        @error      = e
        @status     = STATUS_FAILED

        raise unless @optional
      end

      # Skip this initializer without executing
      #
      # Used when dependencies fail or when conditionally disabled
      def skip!
        @status = STATUS_SKIPPED
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
          @optional ? '✗ (optional)' : '✗ FAILED'
        when STATUS_SKIPPED
          '⊘ skipped'
        when STATUS_RUNNING
          '⋯ running'
        else
          '○ pending'
        end
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
