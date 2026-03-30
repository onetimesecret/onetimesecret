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
        # @return [BaseStrategy] Appropriate strategy instance
        # @raise [ArgumentError] If provider type is unknown
        #
        def self.for_provider(provider_type)
          normalized = provider_type.to_s.downcase.strip

          strategy_class = PROVIDER_MAP[normalized]

          unless strategy_class
            raise ArgumentError,
              "Unknown mail provider: '#{provider_type}'. " \
              "Valid options: #{PROVIDER_MAP.keys.join(', ')}"
          end

          strategy_class.new
        end
      end
    end
  end
end
