# lib/onetime/billing_config.rb
#
# frozen_string_literal: true

# Optional billing configuration loader
# Returns empty config if billing.yaml doesn't exist
#
# Supports environment-specific config files:
# - etc/billing.test.yaml (when RACK_ENV=test)
# - etc/billing.yaml (default)

require 'yaml'
require 'erb'
require 'singleton'
require_relative 'utils/config_resolver'

module Onetime
  class BillingConfig
    include Singleton

    attr_reader :config, :path, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @path        = Onetime::Utils::ConfigResolver.resolve('billing')
      load_config
    end

    # Whether billing is enabled
    # Returns false if file doesn't exist or enabled is not true
    def enabled?
      config['enabled'].to_s == 'true'
    end

    # Stripe API key
    #
    # Checks ENV['STRIPE_API_KEY'] first, then falls back to config file.
    # This allows environment-based configuration to override file config.
    def stripe_key
      env_key    = ENV.fetch('STRIPE_API_KEY', nil)
      config_key = config['stripe_key']
      result     = env_key || config_key

      # Debug logging on first access only (avoid log spam)
      unless @stripe_key_logged
        @stripe_key_logged = true
        OT.ld '[BillingConfig.stripe_key] Key resolution',
          {
            env_present: !env_key.to_s.strip.empty?,
            config_present: !config_key.to_s.strip.empty?,
            source: if env_key
          'ENV'
          else
          (config_key ? 'config' : 'none')
          end,
            result_prefix: result&.slice(0, 8),
          }
      end

      result
    end

    # Stripe webhook signing secret
    def webhook_signing_secret
      config['webhook_signing_secret']
    end

    # Stripe API version
    def stripe_api_version
      config['stripe_api_version']
    end

    # Schema version
    def schema_version
      config['schema_version']
    end

    # App identifier used in Stripe metadata matching
    def app_identifier
      config['app_identifier']
    end

    # Entitlements configuration
    def entitlements
      config['entitlements'] || {}
    end

    # Plans configuration (includes legacy plans with `legacy: true` flag)
    def plans
      config['plans'] || {}
    end

    # Stripe metadata schema
    def stripe_metadata_schema
      config['stripe_metadata_schema'] || {}
    end

    # Region / jurisdiction for catalog isolation
    #
    # When set (e.g. 'NZ', 'CA'), only Stripe products whose region metadata
    # matches this value will be imported. Returns nil when unset, which means
    # all regions are accepted (backward-compatible pass-through).
    #
    # There is intentionally no "global" default. A deployment either operates
    # in a specific region or regionalization is not applicable (nil).
    # See Billing::RegionNormalizer for the authoritative normalization rules.
    def region
      val = config['region']
      return nil if val.to_s.strip.empty?

      val.to_s.strip.upcase
    end

    # Payment links configuration
    def payment_links
      config['payment_links'] || {}
    end

    # Full billing configuration hash
    # Returns the entire config for backward compatibility
    def billing
      config
    end

    # Reload configuration (useful for testing)
    # Also picks up any changes to BillingConfig.path
    def reload!
      @environment = ENV['RACK_ENV'] || 'development'
      @path        = resolve_config_file
      load_config
      self
    end

    private

    def load_config
      unless @path && File.exist?(@path)
        @config = {}
        return
      end

      erb_template = ERB.new(File.read(@path))
      yaml_content = erb_template.result
      @config      = YAML.safe_load(yaml_content, symbolize_names: false) || {}
    rescue StandardError => ex
      OT.le "[BillingConfig] Error loading billing config: #{ex.message}"
      @config = {}
    end
  end

  # Convenience method for accessing billing configuration
  def self.billing_config
    BillingConfig.instance
  end
end
