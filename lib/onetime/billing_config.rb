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

    class << self
    end

    attr_reader :config, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @config_file = Onetime::Utils::ConfigResolver.resolve('billing')
      load_config
    end

    # Whether billing is enabled
    # Returns false if file doesn't exist or enabled is not true
    def enabled?
      config['enabled'].to_s == 'true'
    end

    # Stripe API key
    def stripe_key
      # STRIPE_API_KEY takes precedence (for testing/VCR recording)
      ENV['STRIPE_API_KEY'] || config['stripe_key']
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
      @config_file = resolve_config_file
      load_config
      self
    end

    private



    def load_config
      unless File.exist?(@config_file)
        @config = {}
        return
      end

      erb_template = ERB.new(File.read(@config_file))
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
