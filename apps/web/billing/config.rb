# apps/web/billing/config.rb
#
# frozen_string_literal: true

require 'yaml'

module Billing
  # Billing configuration and catalog management
  module Config
    # Get path to billing configuration file
    #
    # @return [String] Absolute path to billing.yaml
    def self.billing_config_path
      File.join(Onetime::HOME, 'etc', 'billing.yaml')
    end

    # Get path to billing plans catalog
    #
    # @return [String] Absolute path to billing-plans.yaml
    def self.catalog_path
      File.join(Onetime::HOME, 'etc', 'billing-plans.yaml')
    end

    # Check if billing config file exists
    #
    # @return [Boolean]
    def self.billing_config_exists?
      File.exist?(billing_config_path)
    end

    # Check if catalog file exists
    #
    # @return [Boolean]
    def self.catalog_exists?
      File.exist?(catalog_path)
    end

    # Load entitlements from billing.yaml
    #
    # Loads entitlement definitions from billing configuration.
    # Falls back to billing-plans.yaml for backward compatibility.
    #
    # @return [Hash] Entitlement definitions by ID
    def self.load_entitlements
      # Try billing.yaml first (new location)
      if billing_config_exists?
        config       = YAML.load_file(billing_config_path)
        entitlements = config.dig('billing', 'entitlements')
        return entitlements if entitlements
      end

      # Fall back to billing-plans.yaml (old location)
      if catalog_exists?
        catalog = YAML.load_file(catalog_path)
        return catalog['entitlements'] if catalog['entitlements']
      end

      # No entitlements found
      {}
    rescue Psych::SyntaxError => ex
      OT.le "Failed to load entitlements: #{ex.message}"
      {}
    end

    # Get entitlement definition by ID
    #
    # @param entitlement_id [String] Entitlement identifier
    # @return [Hash, nil] Entitlement definition or nil
    def self.get_entitlement(entitlement_id)
      load_entitlements[entitlement_id.to_s]
    end

    # Check if entitlement exists
    #
    # @param entitlement_id [String] Entitlement identifier
    # @return [Boolean]
    def self.entitlement_exists?(entitlement_id)
      load_entitlements.key?(entitlement_id.to_s)
    end

    # Get entitlements by category
    #
    # @param category [String, Symbol] Entitlement category
    # @return [Hash] Entitlements in category
    def self.entitlements_by_category(category)
      load_entitlements.select do |_id, cap|
        cap['category'] == category.to_s
      end
    end
  end
end
