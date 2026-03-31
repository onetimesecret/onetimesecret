# lib/onetime/domain_validation/sender_strategies/provider_config.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    module SenderStrategies
      # ProviderConfig - Configuration resolver for email provider settings.
      #
      # Loads provider-specific settings from application config with fallback
      # to sensible defaults. This externalizes hardcoded values like AWS regions
      # and SendGrid subdomains to the YAML configuration file.
      #
      # Config structure (in config.yaml):
      #   email_providers:
      #     ses:
      #       region: us-east-1
      #       dkim_selector_count: 3
      #       spf_include: amazonses.com
      #     sendgrid:
      #       subdomain: em
      #       dkim_selectors: [s1, s2]
      #       spf_include: sendgrid.net
      #     lettermint:
      #       dkim_selectors: [lm1, lm2]
      #       spf_include: lettermint.com
      #
      # Usage:
      #   config = ProviderConfig.for('ses')
      #   config[:region]  # => 'us-east-1'
      #
      #   # With explicit overrides (kwargs take precedence)
      #   config = ProviderConfig.for('ses', region: 'eu-west-1')
      #   config[:region]  # => 'eu-west-1'
      #
      module ProviderConfig
        # Hardcoded defaults provide backward compatibility when no config is
        # present. These match the original hardcoded values in each strategy.
        DEFAULTS = {
          'ses' => {
            region: 'us-east-1',
            dkim_selector_count: 3,
            spf_include: 'amazonses.com',
          }.freeze,
          'sendgrid' => {
            subdomain: 'em',
            dkim_selectors: %w[s1 s2].freeze,
            spf_include: 'sendgrid.net',
          }.freeze,
          'lettermint' => {
            dkim_selectors: %w[lm1 lm2].freeze,
            spf_include: 'lettermint.com',
          }.freeze,
        }.freeze

        # Returns merged configuration for a provider.
        #
        # Merge precedence (lowest to highest):
        #   1. DEFAULTS (hardcoded fallbacks)
        #   2. OT.conf['email_providers'][provider] (YAML config)
        #   3. overrides (explicit kwargs)
        #
        # @param provider [String] Provider name ('ses', 'sendgrid', 'lettermint')
        # @param overrides [Hash] Explicit overrides that take precedence
        # @return [Hash] Merged configuration with symbol keys
        # @raise [ArgumentError] If config values fail validation
        #
        def self.for(provider, **overrides)
          normalized = provider.to_s.downcase.strip
          defaults   = DEFAULTS.fetch(normalized, {})
          from_conf  = load_from_config(normalized)

          # Filter out nil values to avoid overwriting defaults with nil
          effective_overrides = overrides.compact

          # Merge with precedence: defaults < config < overrides
          config = defaults.merge(from_conf).merge(effective_overrides)
          validate_config!(normalized, config)
          config
        end

        # Loads provider config from OT.conf['email_providers'].
        #
        # @param provider [String] Provider name
        # @return [Hash] Config hash with symbol keys, empty if not configured
        #
        def self.load_from_config(provider)
          return {} unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

          providers_conf = OT.conf['email_providers'] || {}
          provider_conf  = providers_conf[provider] || {}

          # Symbolize keys for consistency with DEFAULTS
          symbolize_keys(provider_conf)
        end

        # Returns all configured providers (from DEFAULTS + any in config).
        #
        # @return [Array<String>] Provider names
        #
        def self.available_providers
          config_providers = if defined?(OT) && OT.respond_to?(:conf) && OT.conf
            (OT.conf['email_providers'] || {}).keys
          else
            []
          end

          (DEFAULTS.keys + config_providers).uniq.sort
        end

        # Deep symbolize keys for a hash. Handles nested hashes and arrays.
        #
        # @param hash [Hash] Input hash with string or symbol keys
        # @return [Hash] Hash with all keys symbolized
        #
        def self.symbolize_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(key, value), result|
            sym_key         = key.to_sym
            result[sym_key] = case value
                              when Hash then symbolize_keys(value)
                              when Array then value.map { |v| v.is_a?(Hash) ? symbolize_keys(v) : v }
                              else value
                              end
          end
        end

        # Validate provider-specific configuration values.
        #
        # @param provider [String] Provider name
        # @param config [Hash] Merged configuration
        # @raise [ArgumentError] If validation fails
        #
        def self.validate_config!(provider, config)
          case provider
          when 'ses'
            region = config[:region]
            unless region.nil? || region.match?(/\A[a-z]{2}-[a-z]+-\d+\z/)
              raise ArgumentError, "Invalid SES region: #{region}"
            end
          when 'sendgrid'
            subdomain = config[:subdomain]
            unless subdomain.nil? || subdomain.match?(/\A[a-z0-9-]+\z/i)
              raise ArgumentError, "Invalid subdomain: #{subdomain}"
            end
          end
          # Other providers have no specific validation yet
        end

        private_class_method :load_from_config, :symbolize_keys, :validate_config!
      end
    end
  end
end
