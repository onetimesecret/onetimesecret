# apps/web/billing/cli/catalog_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
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
        print_validation_results(result.errors, result.warnings, strict, result.valid)
      end

      private

      def show_progress(message)
        puts message
      end

      def print_plan_summary(summary)
        valid   = summary[:valid] || []
        invalid = summary[:invalid] || []

        puts
        if valid.any?
          puts "VALID (#{valid.size}) " + ('-' * (60 - "VALID (#{valid.size}) ".length))
          valid.sort_by { |p| -(p[:display_order] || 0) }.each do |plan|
            marker = plan[:tier] == 'free' ? '*' : ' '
            name   = (plan[:name] || plan[:id]).to_s
            puts "  #{marker} #{name.ljust(20)} (#{plan[:id]})"
          end
          puts if invalid.any?
        end

        if invalid.any?
          puts "INVALID (#{invalid.size}) " + ('-' * (60 - "INVALID (#{invalid.size}) ".length))
          invalid.each do |plan|
            name = (plan[:name] || plan[:id]).to_s
            puts "    #{name} (#{plan[:id]})"
          end
        end

        if summary[:has_free_tier]
          puts
          puts '  * Free tier valid in catalog, does not have a Stripe product'
        end
      end

      def print_validation_results(errors, warnings, strict, valid)
        puts
        puts '-' * 62

        if errors.any?
          puts "VALIDATION FAILED: #{errors.size} error(s) found"
          puts '-' * 62
          puts
          errors.each { |e| puts "  #{e}" }
          puts
          exit 1
        elsif warnings.any? && strict
          puts "VALIDATION FAILED: #{warnings.size} warning(s) in strict mode"
          puts '-' * 62
          puts
          warnings.each { |w| puts "  #{w}" }
          puts
          exit 1
        elsif warnings.any?
          puts 'VALIDATION PASSED (warnings only)'
          puts '-' * 62
          puts
          puts "  #{warnings.size} warning(s):"
          puts
          warnings.each { |w| puts "  #{w}" }
          puts
        else
          puts 'VALIDATION PASSED'
          puts '-' * 62
          puts
        end

        exit(valid ? 0 : 1)
      end
    end
  end
end

Onetime::CLI.register 'billing catalog validate', Onetime::CLI::BillingCatalogValidateCommand
