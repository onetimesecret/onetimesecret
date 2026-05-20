# apps/web/billing/operations/catalog/validate.rb
#
# frozen_string_literal: true

require 'yaml'
require 'json_schemer'

module Billing
  module Operations
    module Catalog
      # Validate billing catalog YAML structure using JSON Schema.
      #
      # Validates local catalog structure only. For Stripe product metadata
      # validation, use `bin/ots billing products validate`.
      #
      # @example
      #   result = Validate.call(strict: true)
      #   if result.valid
      #     puts "Catalog valid with #{result.plans_validated} plans"
      #   else
      #     result.errors.each { |e| puts "ERROR: #{e}" }
      #   end
      #
      class Validate
        Result = Data.define(
          :success,
          :valid,
          :plans_validated,
          :errors,
          :warnings,
          :plan_summary,
        ) do
          def initialize(success:, valid: false, plans_validated: 0, errors: [], warnings: [], plan_summary: {})
            super
          end
        end

        # @param strict [Boolean] Fail on warnings (default: only fail on errors)
        # @param progress [Proc, nil] Called with status messages
        # @return [Result]
        def self.call(strict: false, progress: nil)
          new(strict: strict, progress: progress).call
        end

        def initialize(strict:, progress:)
          @strict   = strict
          @progress = progress
        end

        def call
          catalog_path = Billing::Config.config_path
          schema_path  = File.join(Onetime::HOME, 'generated', 'schemas', 'config', 'billing.schema.json')

          unless File.exist?(catalog_path)
            return Result.new(success: false, errors: ["Catalog file not found: #{catalog_path}"])
          end

          unless File.exist?(schema_path)
            return Result.new(success: false, errors: ["Schema file not found: #{schema_path}"])
          end

          report("Validating catalog structure: #{catalog_path}")

          catalog = load_catalog(catalog_path)
          return Result.new(success: false, errors: ['Failed to load catalog (YAML syntax error)']) unless catalog

          schema = load_schema(schema_path)
          return Result.new(success: false, errors: ['Failed to load schema (JSON syntax error)']) unless schema

          errors   = []
          warnings = []

          validate_with_schema(catalog, schema, errors)
          validate_entitlements_references(catalog, errors, warnings)
          validate_price_consistency(catalog, warnings)

          plans        = catalog['plans'] || {}
          plan_summary = build_plan_summary(catalog, errors)

          valid = errors.empty? && (!@strict || warnings.empty?)

          Result.new(
            success: true,
            valid: valid,
            plans_validated: plans.size,
            errors: errors,
            warnings: warnings,
            plan_summary: plan_summary,
          )
        rescue StandardError => ex
          Result.new(success: false, errors: ["#{ex.class}: #{ex.message}"])
        end

        private

        def report(message)
          @progress&.call(message)
        end

        def load_catalog(path)
          erb_template = ERB.new(File.read(path))
          yaml_content = erb_template.result
          YAML.safe_load(yaml_content, permitted_classes: [Symbol], symbolize_names: false)
        rescue StandardError
          nil
        end

        def load_schema(path)
          JSON.parse(File.read(path))
        rescue StandardError
          nil
        end

        def validate_with_schema(catalog, schema, errors)
          schemer           = JSONSchemer.schema(schema)
          validation_errors = schemer.validate(catalog).to_a

          validation_errors.each do |error|
            location = error['data_pointer'].empty? ? 'root' : error['data_pointer']
            message  = error['error'] || error['type']
            errors << "Schema validation: #{location}: #{message}"
          end
        end

        def validate_entitlements_references(catalog, _errors, warnings)
          entitlements = Billing::Config.load_entitlements

          return if entitlements.empty?

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

          if catalog['legacy_plans']&.any?
            warnings << 'DEPRECATED: legacy_plans section found. Move plans to plans with legacy: true flag.'
          end
        end

        def validate_price_consistency(catalog, warnings)
          plans = catalog['plans'] || {}

          plans.each do |plan_id, plan_data|
            prices = plan_data['prices'] || []

            next if plan_data['tier'] == 'free'

            if prices.empty?
              warnings << "Plan #{plan_id}: No prices defined (expected for paid tier)"
            end

            intervals = prices.map { |p| p['interval'] }.uniq
            if intervals.size == 1
              missing = (%w[month year] - intervals).first
              warnings << "Plan #{plan_id}: Missing #{missing}ly pricing (recommend both intervals)"
            end

            interval_counts = prices.group_by { |p| p['interval'] }.transform_values(&:count)
            interval_counts.each do |interval, count|
              if count > 1
                warnings << "Plan #{plan_id}: Duplicate #{interval}ly prices (#{count} found)"
              end
            end
          end
        end

        def build_plan_summary(catalog, errors)
          plans         = catalog['plans'] || {}
          valid_plans   = []
          invalid_plans = []

          plans.each do |plan_id, data|
            has_errors = errors.any? { |e| e.include?("Plan #{plan_id}:") || e.include?("/plans/#{plan_id}") }

            if has_errors
              invalid_plans << { id: plan_id, name: data['name'], tier: data['tier'] }
            else
              valid_plans << { id: plan_id, name: data['name'], tier: data['tier'] }
            end
          end

          {
            valid: valid_plans,
            invalid: invalid_plans,
            has_free_tier: valid_plans.any? { |p| p[:tier] == 'free' },
          }
        end
      end
    end
  end
end
