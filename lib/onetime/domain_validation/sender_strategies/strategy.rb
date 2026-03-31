# lib/onetime/domain_validation/sender_strategies/strategy.rb
#
# frozen_string_literal: true

#
# Sender Domain Validation Strategy Pattern
#
# Provides an abstraction layer for different mail provider DNS validation
# requirements. Each provider (SES, SendGrid, Lettermint) needs specific
# DNS records (DKIM, SPF, MX) configured for the sending domain.
#
# Usage:
#   strategy = Onetime::DomainValidation::SenderStrategies::SenderStrategy.for_provider('ses')
#   records  = strategy.required_dns_records(mailer_config)
#   results  = strategy.verify_dns_records(mailer_config)
#

require_relative 'base_strategy'
require_relative 'ses_validation'
require_relative 'sendgrid_validation'
require_relative 'lettermint_validation'

module Onetime
  module DomainValidation
    module SenderStrategies
      # Factory class for creating sender domain validation strategies
      class SenderStrategy
        PROVIDER_MAP = {
          'ses' => SesValidation,
          'sendgrid' => SendgridValidation,
          'lettermint' => LettermintValidation,
        }.freeze

        # Factory method to create appropriate strategy based on provider type.
        #
        # @param provider_type [String] One of 'ses', 'sendgrid', 'lettermint'
        # @param options [Hash] Provider-specific options forwarded to the
        #   strategy constructor (e.g. region: for SES, subdomain: for SendGrid).
        # @return [BaseStrategy] Appropriate strategy instance
        # @raise [ArgumentError] If provider type is unknown
        #
        def self.for_provider(provider_type, options = {})
          normalized = provider_type.to_s.downcase.strip

          strategy_class = PROVIDER_MAP[normalized]

          unless strategy_class
            raise ArgumentError,
              "Unknown mail provider: '#{provider_type}'. " \
              "Valid providers: #{PROVIDER_MAP.keys.join(', ')}"
          end

          # Validate options against the strategy's declared whitelist.
          # Reject unknown keys at the factory boundary with a clear
          # error message naming the provider, rather than letting Ruby's
          # kwarg check leak constructor details.
          accepted = strategy_class.accepted_options
          unknown  = options.keys - accepted
          unless unknown.empty?
            raise ArgumentError,
              "Unknown option(s) #{unknown.inspect} for provider '#{normalized}'. " \
              "Accepted: #{accepted.empty? ? 'none' : accepted.inspect}"
          end

          strategy_class.new(**options.slice(*accepted))
        end
      end
    end
  end
end
