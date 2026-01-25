# apps/web/billing/cli/catalog_validate_command.rb
#
# frozen_string_literal: true

require 'yaml'
require 'json_schemer'
require_relative 'helpers'
require_relative '../config'

module Onetime
  module CLI
    # Validate plan catalog YAML structure using JSON Schema
    class BillingCatalogValidateCommand < Command
      include BillingHelpers

      desc 'Validate plan catalog YAML structure (schema validation only)'

      option :strict,
        type: :boolean,
        default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(strict: false, **)
        boot_application!

        catalog_path = Billing::Config.config_path
        schema_path  = File.join(File.dirname(catalog_path), 'schemas', 'billing.schema.json')

        unless File.exist?(catalog_path)
          puts "❌ Error: Catalog file not found: #{catalog_path}"
          return
        end

        unless File.exist?(schema_path)
          puts "❌ Error: Schema file not found: #{schema_path}"
          return
        end

        puts "Validating catalog structure: #{catalog_path}"
        puts

        # Load catalog and schema
        catalog = load_catalog(catalog_path)
        return unless catalog

        schema = load_schema(schema_path)
        return unless schema

        errors   = []
        warnings = []

        # Validate against JSON Schema
        validate_with_schema(catalog, schema, errors)

        # Additional semantic validations
        validate_entitlements_references(catalog, errors, warnings)
        validate_price_consistency(catalog, warnings)

        # Report results
        print_plan_summary(catalog, errors)
        print_validation_results(errors, warnings, strict)
      end

      private

      def load_catalog(path)
        erb_template = ERB.new(File.read(path))
        yaml_content = erb_template.result
        YAML.safe_load(yaml_content, permitted_classes: [Symbol], symbolize_names: false)
      rescue Psych::SyntaxError => ex
        puts "❌ YAML syntax error: #{ex.message}"
        nil
      rescue StandardError => ex
        puts "❌ Error loading catalog: #{ex.message}"
        nil
      end

      def load_schema(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => ex
        puts "❌ JSON schema syntax error: #{ex.message}"
        nil
      rescue StandardError => ex
        puts "❌ Error loading schema: #{ex.message}"
        nil
      end

      def validate_with_schema(catalog, schema, errors)
        schemer           = JSONSchemer.schema(schema)
        validation_errors = schemer.validate(catalog).to_a

        validation_errors.each do |error|
          # Build human-readable error message
          location = error['data_pointer'].empty? ? 'root' : error['data_pointer']
          message  = error['error'] || error['type']
          errors << "Schema validation: #{location}: #{message}"
        end
      end

      def validate_entitlements_references(catalog, _errors, warnings)
        # Load entitlements from billing.yaml
        entitlements = Billing::Config.load_entitlements

        return if entitlements.empty?

        # Validate plan entitlement references (includes legacy plans with legacy: true flag)
        plans = catalog['plans'] || {}
        plans.each do |plan_id, plan_data|
          plan_entitlements = plan_data['entitlements'] || []
          is_legacy         = plan_data['legacy'] == true
          label             = is_legacy ? "Legacy plan #{plan_id}" : "Plan #{plan_id}"

          plan_entitlements.each do |ent_id|
            unless entitlements.key?(ent_id)
              warnings << "#{label}: references unknown entitlement '#{ent_id}'"
            end
          end
        end

        # Warn if deprecated legacy_plans section exists
        if catalog['legacy_plans']&.any?
          warnings << "DEPRECATED: legacy_plans section found. Move plans to 'plans' with legacy: true flag."
        end
      end

      def validate_price_consistency(catalog, warnings)
        plans = catalog['plans'] || {}

        plans.each do |plan_id, plan_data|
          prices = plan_data['prices'] || []

          # Skip free tier
          next if plan_data['tier'] == 'free'

          # Warn if no prices defined for paid tier
          if prices.empty?
            warnings << "Plan #{plan_id}: No prices defined (expected for paid tier)"
          end

          # Check for both monthly and yearly pricing
          intervals = prices.map { |p| p['interval'] }.uniq
          if intervals.size == 1
            missing = (%w[month year] - intervals).first
            warnings << "Plan #{plan_id}: Missing #{missing}ly pricing (recommend both intervals)"
          end

          # Check for duplicate intervals
          interval_counts = prices.group_by { |p| p['interval'] }.transform_values(&:count)
          interval_counts.each do |interval, count|
            if count > 1
              warnings << "Plan #{plan_id}: Duplicate #{interval}ly prices (#{count} found)"
            end
          end
        end
      end

      def print_validation_results(errors, warnings, strict)
        puts

        if errors.any?
          puts '  ' + ('━' * 62)
          puts "   ❌  VALIDATION FAILED: #{errors.size} error(s) found"
          puts '  ' + ('━' * 62)
          puts
          errors.each { |error| puts "  ✗ #{error}" }
          puts
        elsif warnings.any? && strict
          puts '  ' + ('━' * 62)
          puts "   ❌  VALIDATION FAILED: #{warnings.size} warning(s) in strict mode"
          puts '  ' + ('━' * 62)
          puts
          warnings.each { |warning| puts "  • #{warning}" }
          puts
        elsif warnings.any?
          puts '  ' + ('━' * 62)
          puts '   ✅  VALIDATION PASSED (warnings only)'
          puts '  ' + ('━' * 62)
          puts
          puts "  ⚠️  #{warnings.size} warning(s):"
          puts
          warnings.each { |warning| puts "  • #{warning}" }
          puts
        else
          puts '  ' + ('━' * 62)
          puts '   ✅  VALIDATION PASSED'
          puts '  ' + ('━' * 62)
          puts
        end

        # Exit successfully if no errors, and either no warnings or not in strict mode
        if errors.any? || (warnings.any? && strict)
          exit 1
        else
          exit 0
        end
      end

      def print_plan_summary(catalog, errors)
        plans = catalog['plans'] || {}

        # Categorize by validation status
        valid         = []
        invalid       = []
        has_free_tier = false

        plans.each do |plan_id, data|
          has_errors = errors.any? { |e| e.start_with?("Plan #{plan_id}:") }

          if has_errors
            invalid << [plan_id, data]
          else
            valid << [plan_id, data]
            has_free_tier = true if data['tier'] == 'free'
          end
        end

        puts
        if valid.any?
          puts "┌─ VALID (#{valid.size}) " + ('─' * (67 - "VALID (#{valid.size}) ".length - 4))
          valid.sort_by { |_id, data| -(data['display_order'] || 0) }.each do |plan_id, data|
            marker = data['tier'] == 'free' ? '*' : ' '
            puts "  #{marker} ✓ #{data['name'].ljust(20)} (#{plan_id})"
          end
          puts ' ' * 67
          puts '└' + ('─' * 67)
          puts if invalid.any?
        end

        if invalid.any?
          puts "┌─ INVALID (#{invalid.size}) " + ('─' * (67 - "INVALID (#{invalid.size}) ".length - 4))
          invalid.sort_by { |_id, data| -(data['display_order'] || 0) }.each do |plan_id, data|
            puts "    ✗ #{data['name'] || plan_id} (#{plan_id})"
          end
          puts ' ' * 67
          puts '└' + ('─' * 67)
        end

        if has_free_tier
          puts
          puts '  * Free tier valid in catalog, does not have a Stripe product'
        end
      end
    end
  end
end

Onetime::CLI.register 'billing catalog validate', Onetime::CLI::BillingCatalogValidateCommand
