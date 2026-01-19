# lib/onetime/domain_validation/strategy.rb
#
# frozen_string_literal: true

#
# Domain Validation Strategy Pattern
#
# Provides an abstraction layer for different domain validation and certificate
# management approaches. This allows the system to work with various backends:
# - Approximated (custom-domains-as-a-service)
# - Caddy on-demand TLS
# - External/manual certificate management
# - Custom implementations
#
# Usage:
#   strategy = Onetime::DomainValidation::Strategy.for_config(config)
#   result = strategy.validate_ownership(custom_domain)
#   cert_status = strategy.request_certificate(custom_domain)
#

require_relative 'features'
require_relative 'approximated_client'
require_relative 'base_strategy'
require_relative 'approximated_strategy'
require_relative 'passthrough_strategy'
require_relative 'caddy_on_demand_strategy'

module Onetime
  module DomainValidation
    # Factory class for creating domain validation strategies
    class Strategy
      # Factory method to create appropriate strategy based on configuration
      #
      # @param config [Hash] Configuration hash from OT.conf
      # @return [BaseStrategy] Appropriate strategy instance
      # @raise [ArgumentError] If strategy is unknown and strict mode is enabled
      def self.for_config(config)
        strategy_name = config.dig('features', 'domains', 'validation_strategy') || 'passthrough'
        strict_mode   = config.dig('features', 'domains', 'strict_strategy') == true

        strategy = case strategy_name.downcase
                   when 'approximated'
                     ApproximatedStrategy.new(config)
                   when 'passthrough', 'external'
                     PassthroughStrategy.new(config)
                   when 'caddy_on_demand', 'caddy'
                     CaddyOnDemandStrategy.new(config)
                   else
                     handle_unknown_strategy(strategy_name, strict_mode, config)
                   end

        OT.ld "[DomainValidation] Using strategy: #{strategy.class.name}" # reduce 'info' noise
        strategy
      end

      # Handles unknown strategy configuration
      #
      # @param strategy_name [String] The unknown strategy name
      # @param strict_mode [Boolean] Whether to raise error or fall back
      # @param config [Hash] Configuration hash
      # @return [BaseStrategy] Fallback strategy instance
      # @raise [ArgumentError] If strict mode is enabled
      def self.handle_unknown_strategy(strategy_name, strict_mode, config)
        if strict_mode
          raise ArgumentError,
            "Unknown domain validation strategy: '#{strategy_name}'. " \
            'Valid options: approximated, passthrough, caddy_on_demand'
        end

        OT.le "[DomainValidation] Unknown strategy: '#{strategy_name}', " \
              'falling back to passthrough mode. Set strict_strategy: true to fail instead.'
        PassthroughStrategy.new(config)
      end
    end
  end
end
