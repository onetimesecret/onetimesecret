# apps/web/billing/cli/catalog_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'validation_helpers'
require_relative '../operations/catalog/validate'

module Onetime
  module CLI
    # Validate plan catalog YAML structure using JSON Schema
    #
    # NOTE: This command validates local catalog structure only.
    # For Stripe product metadata validation (field name variants, typos,
    # unknown fields), run: bin/ots billing products validate
    class BillingCatalogValidateCommand < Command
      include BillingHelpers
      include ValidationHelpers

      desc 'Validate plan catalog YAML structure (schema validation only)'

      option :strict,
        type: :boolean,
        default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(strict: false, **)
        boot_application!

        result = Billing::Operations::Catalog::Validate.call(
          strict: strict,
          progress: method(:show_progress),
        )

        puts

        unless result.success
          result.errors.each { |e| puts "Error: #{e}" }
          exit 1
        end

        print_plan_summary(result.plan_summary)
        print_errors_section(result.errors) if result.errors.any?
        print_warnings_section(result.warnings) if result.warnings.any?
        print_final_status(result.errors, result.warnings, strict)

        exit(result.valid ? 0 : 1)
      end

      private

      def show_progress(message)
        puts message
      end

      def print_plan_summary(summary)
        valid   = summary[:valid] || []
        invalid = summary[:invalid] || []

        puts
        print_plan_summary_group('VALID', valid) if valid.any?
        puts if valid.any? && invalid.any?
        print_plan_summary_group('INVALID', invalid, indent: '    ') if invalid.any?

        return unless summary[:has_free_tier]

        puts
        puts '  * Free tier valid in catalog, does not have a Stripe product'
      end

      def print_plan_summary_group(label, plans, indent: '  ')
        heading = "#{label} (#{plans.size}) "
        puts heading + ('-' * (60 - heading.length))

        sorted = plans.sort_by { |p| -(p[:display_order] || 0) }
        sorted.each do |plan|
          name = (plan[:name] || plan[:id]).to_s
          if label == 'VALID'
            marker = plan[:tier] == 'free' ? '*' : ' '
            puts "#{indent}#{marker} #{name.ljust(20)} (#{plan[:id]})"
          else
            puts "#{indent}#{name} (#{plan[:id]})"
          end
        end
      end
    end
  end
end

Onetime::CLI.register 'billing catalog validate', Onetime::CLI::BillingCatalogValidateCommand
