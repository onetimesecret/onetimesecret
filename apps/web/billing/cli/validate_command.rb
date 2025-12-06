# apps/web/billing/cli/validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Run all billing validation commands
    class BillingValidateCommand < Command
      include BillingHelpers

      desc 'Run all billing validations (convenience command)'

      option :strict, type: :boolean, default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(strict: false, **)
        boot_application!

        puts '━' * 70
        puts '  BILLING VALIDATION SUITE'
        puts '━' * 70
        puts

        results = {
          catalog: nil,
          products: nil,
          prices: nil,
          plans: nil,
        }

        # 1. Catalog validation (YAML structure)
        results[:catalog] = run_validation('Catalog Structure', strict) do
          system("bin/ots billing catalog validate#{' --strict' if strict}")
        end

        puts
        puts '─' * 70
        puts

        # 2. Products validation (Stripe products metadata)
        if stripe_configured?
          results[:products] = run_validation('Products Metadata', strict) do
            system('bin/ots billing products validate')
          end

          puts
          puts '─' * 70
          puts

          # 3. Prices validation (Stripe prices sanity)
          results[:prices] = run_validation('Prices Configuration', strict) do
            system("bin/ots billing prices validate#{' --strict' if strict}")
          end

          puts
          puts '─' * 70
          puts

          # 4. Plans validation (production readiness)
          results[:plans] = run_validation('Plans Production Readiness', strict) do
            system("bin/ots billing plans validate#{' --strict' if strict}")
          end
        else
          puts '⚠️  Skipping Stripe API validations (no API key configured)'
          results[:products] = :skipped
          results[:prices]   = :skipped
          results[:plans]    = :skipped
        end

        # Print summary
        print_summary(results)

        # Exit with failure if any validation failed
        exit 1 if results.value?(false)
      end

      private

      def run_validation(name, _strict)
        puts "Running: #{name}"
        puts

        yield
      end

      def print_summary(results)
        puts
        puts '━' * 70
        puts '  VALIDATION SUMMARY'
        puts '━' * 70
        puts

        results.each do |validation, result|
          status = case result
                  when true then '✅ PASSED'
                  when false then '❌ FAILED'
                  when :skipped then '⊘  SKIPPED'
                  else '❓ UNKNOWN'
                  end

          name = validation.to_s.split('_').map(&:capitalize).join(' ')
          puts "  #{name.ljust(25)} #{status}"
        end

        puts
        passed_count  = results.values.count(true)
        failed_count  = results.values.count(false)
        skipped_count = results.values.count(:skipped)

        if failed_count.zero?
          puts '  ✅  ALL VALIDATIONS PASSED'
        else
          puts "  ❌  #{failed_count} VALIDATION(S) FAILED"
        end

        puts "  #{passed_count} passed, #{failed_count} failed, #{skipped_count} skipped"
        puts
        puts '━' * 70
      end
    end
  end
end

Onetime::CLI.register 'billing validate', Onetime::CLI::BillingValidateCommand
