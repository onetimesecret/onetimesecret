# lib/onetime/mail/sender_strategies.rb
#
# frozen_string_literal: true

require_relative 'sender_strategies/base_sender_strategy'
require_relative 'sender_strategies/ses_sender_strategy'
require_relative 'sender_strategies/sendgrid_sender_strategy'
require_relative 'sender_strategies/lettermint_sender_strategy'
require_relative 'sender_strategies/smtp_sender_strategy'

module Onetime
  module Mail
    # SenderStrategies - Factory for sender domain provisioning strategies.
    #
    # Provides a factory method to create the appropriate sender strategy
    # based on the mail provider name.
    #
    # Usage:
    #   strategy = Onetime::Mail::SenderStrategies.for_provider('ses')
    #   result = strategy.provision_dns_records(mailer_config, credentials: creds)
    #
    # Supported providers:
    #   - ses: AWS SES DKIM provisioning
    #   - sendgrid: SendGrid domain authentication
    #   - lettermint: Lettermint domain setup
    #   - smtp: No-op (manual DNS configuration)
    #
    module SenderStrategies
      # Registry of provider names to strategy classes.
      #
      PROVIDER_STRATEGIES = {
        'ses' => SESSenderStrategy,
        'sendgrid' => SendGridSenderStrategy,
        'lettermint' => LettermintSenderStrategy,
        'smtp' => SMTPSenderStrategy,
      }.freeze

      # List of provider names that support automated provisioning.
      #
      PROVISIONING_PROVIDERS = %w[ses sendgrid lettermint].freeze

      class << self
        # Create a sender strategy for the given provider.
        #
        # @param provider [String, Symbol] Provider name ('ses', 'sendgrid', etc.)
        # @param config [Hash] Optional strategy configuration
        # @return [BaseSenderStrategy] The appropriate strategy instance
        # @raise [ArgumentError] If provider is unknown
        #
        # @example
        #   strategy = SenderStrategies.for_provider('ses')
        #   strategy = SenderStrategies.for_provider(:sendgrid, api_key: 'xxx')
        #
        def for_provider(provider, config = {})
          provider_key = provider.to_s.downcase

          strategy_class = PROVIDER_STRATEGIES[provider_key]

          unless strategy_class
            raise ArgumentError,
              "Unknown sender strategy provider: #{provider}. " \
              "Supported: #{PROVIDER_STRATEGIES.keys.join(', ')}"
          end

          strategy_class.new(config)
        end

        # Check if a provider supports automated DNS provisioning.
        #
        # @param provider [String, Symbol] Provider name
        # @return [Boolean] true if provider supports provisioning
        #
        def supports_provisioning?(provider)
          PROVISIONING_PROVIDERS.include?(provider.to_s.downcase)
        end

        # List all supported provider names.
        #
        # @return [Array<String>] Provider names
        #
        def supported_providers
          PROVIDER_STRATEGIES.keys
        end
      end
    end
  end
end
