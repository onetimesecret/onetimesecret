# apps/web/billing/config.rb
#
# frozen_string_literal: true

require 'yaml'
require 'erb'
require_relative '../../../lib/onetime/utils/config_resolver'

module Billing
  # Billing configuration and catalog management
  module Config
    # Staleness threshold for the plan catalog.
    # Used for:
    # - catalog_synced_at expiration (triggers re-sync on boot)
    # - Catalog staleness checks in BillingCatalog initializer
    #
    # Plan hashes themselves have no TTL; they persist until explicitly
    # removed by clear_cache, prune_stale_plans, or destroy!.
    #
    # @return [Integer] Threshold in seconds (12 hours)
    CATALOG_TTL = 12 * 60 * 60
    # Get path to billing configuration file
    #
    # Uses ConfigResolver to automatically load test config (spec/billing.test.yaml)
    # when RACK_ENV=test, otherwise loads production config (etc/billing.yaml).
    #
    # @return [String, nil] Absolute path to billing config file, or nil if not found
    def self.config_path
      Onetime::Utils::ConfigResolver.resolve('billing')
    end

    # Check if billing config file exists
    #
    # @return [Boolean]
    def self.config_exists?
      path = config_path
      path && File.exist?(path)
    end

    # Safely load and parse billing YAML configuration
    #
    # Processes ERB templates and uses safe YAML loading to prevent
    # arbitrary code execution from malicious YAML content.
    #
    # @return [Hash] Parsed configuration or empty hash on error
    def self.safe_load_config
      return {} unless config_exists?

      erb_template = ERB.new(File.read(config_path))
      yaml_content = erb_template.result
      YAML.safe_load(yaml_content, permitted_classes: [Symbol], symbolize_names: false) || {}
    rescue Psych::SyntaxError => ex
      OT.le "YAML syntax error in billing config: #{ex.message}"
      {}
    rescue StandardError => ex
      OT.le "Failed to load billing config: #{ex.message}"
      {}
    end

    # Load entitlements from billing.yaml
    #
    # Loads entitlement definitions from billing configuration with flat structure.
    #
    # @return [Hash] Entitlement definitions by ID
    def self.load_entitlements
      config = safe_load_config
      config['entitlements'] || {}
    end

    # Load plans from billing.yaml
    #
    # Loads plan definitions from billing configuration.
    # Legacy plans use `legacy: true` flag in the plans section.
    #
    # @return [Hash] Plan definitions by ID
    def self.load_plans
      config = safe_load_config
      config['plans'] || {}
    end

    # Load full catalog from billing.yaml
    #
    # Loads complete billing catalog including schema_version, app_identifier, entitlements, and plans.
    #
    # @return [Hash] Full catalog hash
    def self.load_catalog
      config = safe_load_config
      return {} if config.empty?

      {
        'schema_version' => config['schema_version'],
        'app_identifier' => config['app_identifier'],
        'entitlements' => config['entitlements'] || {},
        'plans' => config['plans'] || {},
      }
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
      load_entitlements.select do |_id, ent|
        ent['category'] == category.to_s
      end
    end

    # Get all entitlements grouped by category
    #
    # Returns entitlement IDs organized by their category.
    # Used by the entitlements API endpoint for documentation.
    #
    # @return [Hash<String, Array<String>>] Category => entitlement IDs
    #
    # @example
    #   Billing::Config.entitlements_grouped_by_category
    #   # => {
    #   #   "core" => ["create_secrets", "view_receipt"],
    #   #   "collaboration" => ["manage_teams", "manage_members"],
    #   #   ...
    #   # }
    def self.entitlements_grouped_by_category
      load_entitlements.each_with_object({}) do |(id, definition), grouped|
        category            = definition['category'] || 'uncategorized'
        grouped[category] ||= []
        grouped[category] << id
      end
    end
  end
end
