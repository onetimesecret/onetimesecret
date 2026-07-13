# lib/onetime/cli/customers/plan_set_command.rb
#
# frozen_string_literal: true

# Set a customer's plan (planid).
#
# Usage:
#   bin/ots customers plan set user@example.com identity_plus_v1        # confirm, then set
#   bin/ots customers plan set ur1234567890abcdef free_v1 --yes         # skip confirmation
#   bin/ots customers plan set 123 team_plus_v1 --json                  # machine output
#
# The mutation + admin audit event is performed by the shared
# Auth::Operations::Customers::SetPlan op (the single implementation; the colonel
# UpdateUserPlan Logic class is the other adapter). That op does NOT validate the
# planid against the billing catalog — catalog validation is the adapter's job,
# so this command checks it up front via Billing::BillingService.valid_plan_id?
# (the same predicate the colonel adapter uses), refusing unknown planids before
# any mutation. The CLI runs outside the auth/billing autoloaders, so require
# them explicitly.
require 'json'
require 'auth/operations/customers/set_plan'
require 'billing/lib/billing_service'
require 'billing/lib/plan_validator'

module Onetime
  module CLI
    # Landing command for the `customers plan` group. Required so the group node
    # carries a command object: `customers` is itself a registered command (not a
    # bare group), and dry-cli's help for a command enumerates its children by
    # `.description` — a nil intermediate node (a group with no command) crashes
    # `bin/ots customers --help`. Registering this makes `customers plan` a real,
    # describable node.
    class CustomersPlanCommand < Command
      desc "Manage a customer's plan"

      def call(**)
        puts 'Usage:'
        puts '  bin/ots customers plan set IDENTIFIER PLANID   # Set plan (validated against catalog)'
      end
    end

    class CustomersPlanSetCommand < Command
      include Customers::Shared

      desc "Set a customer's plan (validated against the billing catalog)"

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'
      argument :planid,
        type: :string,
        required: true,
        desc: 'Target plan id (must exist in the billing catalog or config)'

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, planid:, yes: false, json: false, **)
        boot_application!

        customer = resolve_target(identifier, json: json)
        planid   = planid.to_s.strip

        unless Billing::BillingService.valid_plan_id?(planid)
          error_exit(
            "Unknown plan id '#{planid}'. Valid plans: #{available_plans_hint}",
            json: json,
          )
        end

        obscured = customer.obscure_email
        from     = customer.planid.to_s

        unless yes
          if json
            error_exit('Refusing to change plan without --yes in --json mode', json: true)
          end

          print "Set plan for #{obscured} from '#{from.empty? ? '(none)' : from}' to '#{planid}'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::SetPlan.new(
          customer: customer,
          planid: planid,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-customers-plan-set] #{obscured} #{result.from} -> #{result.to} status=#{result.status}"

        if json
          output_json(result)
        else
          output_text(result, obscured)
        end
      end

      private

      def output_text(result, obscured)
        if result.status == :no_change
          puts "#{obscured} already on plan '#{result.to}'"
          return
        end

        from_display = result.from.to_s.empty? ? '(none)' : result.from
        puts "#{obscured}: #{from_display} -> #{result.to}"
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          extid: result.customer.extid,
          email: result.customer.obscure_email,
          from: result.from,
          to: result.to,
        )
      end

      # Sorted list of valid plan ids for the "unknown plan" error. Only reached
      # on the error path (invalid planid), so the catalog scan cost is off the
      # happy path.
      def available_plans_hint
        Billing::PlanValidator.available_plan_ids.join(', ')
      rescue StandardError
        '(catalog unavailable)'
      end

      # Resolve to a mutable, non-anonymous Customer or exit non-zero with a
      # json-aware error. resolve_customer is the shared identifier resolver
      # (email / extid / numeric Rodauth account id).
      def resolve_target(identifier, json:)
        error_exit('Identifier is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot set plan on anonymous customer', json: json) if customer.anonymous?

        customer
      end

      def error_exit(message, json:)
        if json
          puts JSON.generate({ error: message })
        else
          puts "Error: #{message}"
        end
        exit 1
      end
    end

    register 'customers plan', CustomersPlanCommand
    register 'customers plan set', CustomersPlanSetCommand
  end
end
