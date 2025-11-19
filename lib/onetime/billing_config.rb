# lib/onetime/billing_config.rb
#
# frozen_string_literal: true

# Optional billing configuration loader
# Returns empty config if billing.yaml doesn't exist

require 'yaml'
require 'erb'
require 'singleton'

module Onetime
  class BillingConfig
    include Singleton

    attr_reader :config

    def initialize
      @config_file = File.join(Onetime::HOME, 'etc/billing.yaml')
      load_config
    end

    # Whether billing is enabled
    # Returns false if file doesn't exist or enabled is not true
    def enabled?
      config.dig('billing', 'enabled').to_s == 'true'
    end

    # Stripe API key
    def stripe_key
      config.dig('billing', 'stripe_key')
    end

    # Stripe webhook signing secret
    def webhook_signing_secret
      config.dig('billing', 'webhook_signing_secret')
    end

    # Payment links configuration
    def payment_links
      config.dig('billing', 'payment_links') || {}
    end

    # Full billing configuration hash
    def billing
      config['billing'] || {}
    end

    # Reload configuration (useful for testing)
    def reload!
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
      @config = YAML.safe_load(yaml_content, symbolize_names: false) || {}
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
