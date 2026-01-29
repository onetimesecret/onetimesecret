# frozen_string_literal: true

module Migration
  module Transforms
    # Base class for all Kiba transforms.
    #
    # Provides:
    # - DSL for declaring required lookups
    # - Stats tracking
    # - Access to shared registry
    #
    # Usage:
    #   class MyTransform < BaseTransform
    #     requires_lookups :email_to_customer, :email_to_org
    #
    #     def process(record)
    #       # Transform logic here
    #       record
    #     end
    #   end
    #
    class BaseTransform
      class << self
        # Declare lookups required by this transform.
        # Can be called multiple times; lookups are accumulated and deduplicated.
        #
        # @param names [Array<Symbol>] Lookup names
        #
        def requires_lookups(*names)
          @required_lookups ||= []
          @required_lookups.concat(names)
          @required_lookups.uniq!
        end

        # Get required lookups for this transform.
        #
        # @return [Array<Symbol>]
        #
        def required_lookups
          @required_lookups || []
        end
      end

      attr_reader :registry, :stats

      # @param registry [LookupRegistry, nil] Lookup registry (optional)
      # @param stats [Hash, nil] Stats hash for tracking (optional)
      #
      def initialize(registry: nil, stats: nil)
        @registry = registry
        @stats = stats || {}

        validate_lookups! if registry
      end

      # Process a single record.
      #
      # @param record [Hash] Input record
      # @return [Hash, nil] Transformed record, or nil to filter out
      #
      def process(record)
        raise NotImplementedError, "#{self.class}#process must be implemented"
      end

      protected

      # Increment a stat counter.
      #
      # @param key [Symbol] Stat key
      # @param amount [Integer] Amount to increment
      #
      def increment_stat(key, amount = 1)
        @stats[key] = (@stats[key] || 0) + amount
      end

      # Perform a lookup via the registry.
      #
      # @param name [Symbol] Lookup name
      # @param key [String] Key to look up
      # @param strict [Boolean] Raise on missing
      # @return [String, nil] The value
      #
      def lookup(name, key, strict: false)
        return nil unless @registry

        @registry.lookup(name, key, strict: strict)
      end

      private

      def validate_lookups!
        missing = self.class.required_lookups.reject { |name| @registry.loaded?(name) }
        return if missing.empty?

        raise LookupValidationError,
              "#{self.class} requires lookups not loaded: #{missing.join(', ')}"
      end

      class LookupValidationError < StandardError; end
    end
  end
end
