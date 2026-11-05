# lib/onetime/cli/customers/role_command.rb
#
# frozen_string_literal: true

# CLI command for managing customer roles. This replaces the legacy config-based
# colonel assignment with explicit role management via command line.
#
# Usage:
#   bin/ots customers role promote user@example.com              # Promote to colonel (default)
#   bin/ots customers role promote user@example.com --role admin # Promote to specific role
#   bin/ots customers role demote user@example.com               # Demote to customer
#   bin/ots customers role list                                  # List all colonels
#   bin/ots customers role list --role admin                     # List users with specific role
#
# The actual role mutation + admin audit event is performed by the shared
# Auth::Operations::Customers::SetRole op (single implementation); this command
# owns only CLI concerns (arg parsing, confirmation prompt, output). The CLI
# runs outside the auth app's autoloader, so require the op explicitly.
#
# `bin/ots customers role reconcile` is a separate command registered under
# this one (role_reconcile_command.rb). It is on the write gate; promote and
# demote are not, so this command declares no --apply or --dry-run that they
# would ignore.
require 'auth/operations/customers/set_role'
require 'onetime/cli/customers/shared'

module Onetime
  module CLI
    class CustomersRoleCommand < Command
      desc 'Manage customer roles (promote, demote, list; reconcile is a subcommand)'

      argument :action,
        type: :string,
        required: true,
        desc: 'Action to perform: promote, demote, or list'

      argument :email,
        type: :string,
        required: false,
        desc: 'Email address of the customer (required for promote/demote)'

      option :role,
        type: :string,
        default: 'colonel',
        desc: 'Target role for promotion or listing (colonel, admin, staff, customer)'

      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes. Same flag, same wording and same
      # blank-means-absent handling as every other destructive CLI verb.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      option :force,
        type: :boolean,
        default: false,
        aliases: ['-f'],
        desc: 'Skip confirmation prompt'

      # Valid roles in hierarchy order (highest to lowest). Single source of
      # truth lives on the op; the CLI references it rather than forking a copy.
      VALID_ROLES = Auth::Operations::Customers::SetRole::VALID_ROLES

      def call(action:, email: nil, role: 'colonel', reason: nil, force: false, **)
        boot_application!

        case action.downcase
        when 'promote'
          promote_customer(email, role, force, reason)
        when 'demote'
          demote_customer(email, force, reason)
        when 'list'
          list_customers_by_role(role)
        else
          puts "Unknown action: #{action}"
          puts 'Valid actions: promote, demote, list (and the reconcile subcommand)'
          exit 1
        end
      end

      private

      def promote_customer(email, target_role, force, reason = nil)
        validate_email_provided!(email, 'promote')
        validate_role!(target_role)

        customer = find_customer!(email)
        old_role = customer.role.to_s
        obscured = OT::Utils.obscure_email(email)

        if old_role == target_role
          puts "#{obscured} already has role '#{target_role}'"
          return
        end

        unless force
          print "Promote #{obscured} from '#{old_role}' to '#{target_role}'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::SetRole.new(
          customer: customer,
          role: target_role,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        ).call

        # `promote --role admin` on a colonel is a DEMOTION in effect, so it can
        # hit the last-colonel interlock too. Same handling as demote.
        unless result.status == :success
          puts refusal_message(result.status, obscured)
          exit 1
        end

        puts "#{obscured}: #{old_role} -> #{target_role}"
        OT.info "[role-change] #{customer.objid} promoted: #{old_role} -> #{target_role}"
      end

      def demote_customer(email, force, reason = nil)
        validate_email_provided!(email, 'demote')

        customer = find_customer!(email)
        old_role = customer.role.to_s
        obscured = OT::Utils.obscure_email(email)

        if old_role == 'customer'
          puts "#{obscured} already has role 'customer'"
          return
        end

        unless force
          print "Demote #{obscured} from '#{old_role}' to 'customer'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::SetRole.new(
          customer: customer,
          role: 'customer',
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        ).call

        # The op refuses demoting the last remaining colonel (#4328) — the same
        # interlock the colonel endpoint answers with a 422. The CLI is the
        # DOCUMENTED recovery path out of that state, so it has to say what
        # happened and exit non-zero rather than print a change it did not make.
        # :self_demotion is unreachable here (no acting customer), so it is not
        # branched on; the else arm would catch it if that ever changed.
        unless result.status == :success
          puts refusal_message(result.status, obscured)
          exit 1
        end

        puts "#{obscured}: #{old_role} -> customer"
        OT.info "[role-change] #{customer.objid} demoted: #{old_role} -> customer"
      end

      # @param status [Symbol] a non-:success SetRole::Result status
      # @param obscured [String] the log-safe form of the target's address
      # @return [String]
      def refusal_message(status, obscured)
        case status
        when :last_colonel
          "Error: refusing to demote #{obscured}: they are the last remaining verified colonel. " \
          'Promote and verify another account first (bin/ots customers role promote EMAIL).'
        else
          "Error: role change did not complete for #{obscured} (#{status})"
        end
      end

      def list_customers_by_role(target_role)
        validate_role!(target_role)

        puts "Customers with role '#{target_role}':"
        puts '-' * 40

        # Use multi_index for O(1) lookup instead of O(n) scanning
        customers = Onetime::Customer.find_all_by_role(target_role)

        customers.each do |customer|
          obscured = OT::Utils.obscure_email(customer.email)
          verified = customer.verified? ? 'verified' : 'unverified'
          puts format('  %s (%s)', obscured, verified)
        end

        puts '-' * 40
        puts "Total: #{customers.size}"
      end

      def validate_email_provided!(email, action)
        return if email && !email.empty?

        puts "Error: Email address required for '#{action}' action"
        puts "Usage: bin/ots customers role #{action} user@example.com"
        exit 1
      end

      def validate_role!(role)
        return if VALID_ROLES.include?(role)

        puts "Error: Invalid role '#{role}'"
        puts "Valid roles: #{VALID_ROLES.join(', ')}"
        exit 1
      end

      def find_customer!(email)
        unless Onetime::Customer.email_exists?(email)
          obscured = OT::Utils.obscure_email(email)
          puts "Error: Customer not found: #{obscured}"
          exit 1
        end

        Onetime::Customer.find_by_email(email)
      end
    end

    register 'customers role', CustomersRoleCommand
  end
end
