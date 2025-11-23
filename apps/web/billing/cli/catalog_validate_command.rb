# apps/web/billing/cli/catalog_validate_command.rb
#
# frozen_string_literal: true

require 'yaml'
require_relative 'helpers'
require_relative '../config'

module Onetime
  module CLI
    # Validate plan catalog YAML structure and Stripe consistency
    class BillingCatalogValidateCommand < Command
      include BillingHelpers

      desc 'Validate plan catalog YAML and compare with Stripe'

      option :catalog_only, type: :boolean, default: false,
        desc: 'Only validate YAML structure (skip Stripe comparison)'

      option :strict, type: :boolean, default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(catalog_only: false, strict: false, **)
        boot_application!

        catalog_path = Billing::Config.catalog_path

        unless File.exist?(catalog_path)
          puts "❌ Error: Catalog file not found: #{catalog_path}"
          return
        end

        puts "Validating catalog: #{catalog_path}"
        puts

        # Load and validate YAML structure
        catalog = load_catalog(catalog_path)
        return unless catalog

        errors = []
        warnings = []

        # Validate schema version
        if catalog['schema_version'] != '1.0'
          errors << "Invalid schema_version: #{catalog['schema_version']} (expected: 1.0)"
        end

        # Validate plans structure
        validate_plans_structure(catalog, errors, warnings)

        # Validate capabilities structure
        validate_capabilities_structure(catalog, errors, warnings)

        # Compare with Stripe if not catalog-only mode
        unless catalog_only
          return unless stripe_configured?

          validate_stripe_consistency(catalog, errors, warnings)
        end

        # Report results
        print_validation_results(errors, warnings, strict)
      end

      private

      def load_catalog(path)
        YAML.load_file(path)
      rescue Psych::SyntaxError => e
        puts "❌ YAML syntax error: #{e.message}"
        nil
      rescue StandardError => e
        puts "❌ Error loading catalog: #{e.message}"
        nil
      end

      def validate_plans_structure(catalog, errors, warnings)
        plans = catalog['plans'] || {}

        if plans.empty?
          errors << 'No plans defined in catalog'
          return
        end

        plans.each do |plan_id, plan_data|
          validate_plan_id(plan_id, errors)
          validate_plan_data(plan_id, plan_data, errors, warnings)
        end
      end

      def validate_plan_id(plan_id, errors)
        unless plan_id.match?(/^[a-z_]+_v\d+$/)
          errors << "Invalid plan_id format: #{plan_id} (expected: name_v1 format)"
        end
      end

      def validate_plan_data(plan_id, data, errors, warnings)
        # Required fields (tier is optional for draft plans)
        %w[name capabilities limits].each do |field|
          unless data[field]
            errors << "Plan #{plan_id}: missing required field '#{field}'"
          end
        end

        # Warn about missing tier (incomplete/draft plan)
        unless data['tier']
          warnings << "Plan #{plan_id}: missing tier field (incomplete definition, will be skipped in Stripe sync)"
          return # Skip further validation if tier is missing
        end

        # Validate tier values
        valid_tiers = %w[free single_team multi_team]
        unless valid_tiers.include?(data['tier'])
          errors << "Plan #{plan_id}: invalid tier '#{data['tier']}' (expected: #{valid_tiers.join(', ')})"
        end

        # Warn if free tier (no Stripe product will be created)
        if data['tier'] == 'free'
          warnings << "Plan #{plan_id}: free tier (no Stripe product will be created)"
        end

        # Required fields for non-free, complete plans
        %w[tenancy region].each do |field|
          unless data[field]
            errors << "Plan #{plan_id}: missing required field '#{field}'"
          end
        end

        # Validate tenancy values
        valid_tenancy = %w[multi dedicated]
        unless valid_tenancy.include?(data['tenancy'])
          errors << "Plan #{plan_id}: invalid tenancy '#{data['tenancy']}' (expected: #{valid_tenancy.join(', ')})"
        end

        # Validate limits
        if data['limits']
          data['limits'].each do |resource, value|
            next if value.nil? # null values are acceptable (TBD)

            unless value.is_a?(Integer) && value >= -1
              errors << "Plan #{plan_id}: invalid limit #{resource} = #{value} (expected: integer >= -1 or null)"
            end
          end
        end

        # Validate capabilities array
        if data['capabilities'] && !data['capabilities'].is_a?(Array)
          errors << "Plan #{plan_id}: capabilities must be an array"
        end

        # Validate prices structure (if present)
        if data['prices'] && !data['prices'].is_a?(Array)
          errors << "Plan #{plan_id}: prices must be an array"
        elsif data['prices']
          data['prices'].each_with_index do |price, idx|
            validate_price_structure(plan_id, price, idx, errors, warnings)
          end
        end
      end

      def validate_price_structure(plan_id, price, idx, errors, _warnings)
        %w[interval amount currency].each do |field|
          unless price[field]
            errors << "Plan #{plan_id}, price #{idx}: missing required field '#{field}'"
          end
        end

        valid_intervals = %w[month year]
        unless valid_intervals.include?(price['interval'])
          errors << "Plan #{plan_id}, price #{idx}: invalid interval '#{price['interval']}' (expected: #{valid_intervals.join(', ')})"
        end

        valid_currencies = %w[usd eur cad]
        unless valid_currencies.include?(price['currency'])
          errors << "Plan #{plan_id}, price #{idx}: invalid currency '#{price['currency']}' (expected: #{valid_currencies.join(', ')})"
        end
      end

      def validate_capabilities_structure(catalog, errors, _warnings)
        capabilities = catalog['capabilities'] || {}

        if capabilities.empty?
          errors << 'No capabilities defined in catalog'
          return
        end

        capabilities.each do |cap_id, cap_data|
          unless cap_data['category']
            errors << "Capability #{cap_id}: missing required field 'category'"
          end

          unless cap_data['description']
            errors << "Capability #{cap_id}: missing required field 'description'"
          end
        end
      end

      def validate_stripe_consistency(catalog, errors, warnings)
        puts 'Comparing with Stripe products...'
        puts

        plans = catalog['plans'] || {}

        # Fetch all Stripe products
        stripe_products = Stripe::Product.list(active: true, limit: 100).data.select do |product|
          product.metadata['app'] == 'onetimesecret'
        end

        # Check each plan in catalog
        plans.each do |plan_id, plan_data|
          # Skip free tier (no Stripe product)
          next if plan_id == 'free_v1'

          stripe_product = stripe_products.find do |p|
            p.metadata['plan_id'] == plan_id
          end

          if stripe_product
            validate_stripe_metadata(plan_id, plan_data, stripe_product, warnings)
          else
            warnings << "Plan #{plan_id} defined in catalog but not found in Stripe"
          end
        end

        # Check for Stripe products not in catalog
        stripe_products.each do |product|
          stripe_plan_id = product.metadata['plan_id']
          next unless stripe_plan_id

          unless plans[stripe_plan_id]
            warnings << "Stripe product #{product.id} (#{stripe_plan_id}) not defined in catalog"
          end
        end
      rescue Stripe::StripeError => e
        errors << "Stripe API error: #{e.message}"
      end

      def validate_stripe_metadata(plan_id, plan_data, stripe_product, warnings)
        # Compare tier
        if plan_data['tier'] != stripe_product.metadata['tier']
          warnings << "Plan #{plan_id}: tier mismatch (catalog: #{plan_data['tier']}, Stripe: #{stripe_product.metadata['tier']})"
        end

        # Compare region
        if plan_data['region'] != stripe_product.metadata['region']
          warnings << "Plan #{plan_id}: region mismatch (catalog: #{plan_data['region']}, Stripe: #{stripe_product.metadata['region']})"
        end

        # Compare tenancy
        if plan_data['tenancy'] != stripe_product.metadata['tenancy']
          warnings << "Plan #{plan_id}: tenancy mismatch (catalog: #{plan_data['tenancy']}, Stripe: #{stripe_product.metadata['tenancy']})"
        end

        # Compare capabilities
        catalog_caps = plan_data['capabilities']&.sort || []
        stripe_caps = (stripe_product.metadata['capabilities'] || '').split(',').map(&:strip).sort

        if catalog_caps != stripe_caps
          warnings << "Plan #{plan_id}: capabilities mismatch"
          warnings << "  Catalog: #{catalog_caps.join(', ')}"
          warnings << "  Stripe:  #{stripe_caps.join(', ')}"
        end
      end

      def print_validation_results(errors, warnings, strict)
        puts
        puts '=' * 60

        if errors.any?
          puts "❌ #{errors.size} error(s) found:"
          errors.each { |error| puts "  • #{error}" }
          puts
        end

        if warnings.any?
          puts "⚠️  #{warnings.size} warning(s):"
          warnings.each { |warning| puts "  • #{warning}" }
          puts
        end

        if errors.empty? && warnings.empty?
          puts '✅ Validation passed - no issues found'
          puts
        elsif errors.empty? && !strict
          puts '✅ Validation passed (warnings only)'
          puts
        elsif errors.any? || (warnings.any? && strict)
          puts '❌ Validation failed'
          puts
        end
      end
    end
  end
end

Onetime::CLI.register 'billing catalog validate', Onetime::CLI::BillingCatalogValidateCommand
