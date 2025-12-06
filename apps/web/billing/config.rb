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

    # Load capabilities from billing.yaml
    #
    # Loads capability definitions from billing configuration.
    # Falls back to billing-plans.yaml for backward compatibility.
    #
    # @return [Hash] Capability definitions by ID
    def self.load_capabilities
      # Try billing.yaml first (new location)
      if billing_config_exists?
        config       = YAML.load_file(billing_config_path)
        capabilities = config.dig('billing', 'capabilities')
        return capabilities if capabilities
      end

      # Fall back to billing-plans.yaml (old location)
      if catalog_exists?
        catalog = YAML.load_file(catalog_path)
        return catalog['capabilities'] if catalog['capabilities']
      end

      # No capabilities found
      {}
    rescue Psych::SyntaxError => ex
      OT.le "Failed to load capabilities: #{ex.message}"
      {}
    end

    # Get capability definition by ID
    #
    # @param capability_id [String] Capability identifier
    # @return [Hash, nil] Capability definition or nil
    def self.get_capability(capability_id)
      load_capabilities[capability_id.to_s]
    end

    # Check if capability exists
    #
    # @param capability_id [String] Capability identifier
    # @return [Boolean]
    def self.capability_exists?(capability_id)
      load_capabilities.key?(capability_id.to_s)
    end

    # Get capabilities by category
    #
    # @param category [String, Symbol] Capability category
    # @return [Hash] Capabilities in category
    def self.capabilities_by_category(category)
      load_capabilities.select do |_id, cap|
        cap['category'] == category.to_s
      end
    end
  end
end
