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
#   bin/ots customers role reconcile                             # Report role-index drift (dry run)
#   bin/ots customers role reconcile --apply                     # Confirm, then repair the index
#   bin/ots customers role reconcile --apply --force --json      # Repair, machine-readable
#
# The actual role mutation + admin audit event is performed by the shared
# Auth::Operations::Customers::SetRole op (single implementation); this command
# owns only CLI concerns (arg parsing, confirmation prompt, output). The role
# index check + repair likewise lives in the shared
# Auth::Operations::Customers::ReconcileRoleIndex op. The CLI runs outside the
# auth app's autoloader, so require the ops explicitly.
require 'json'
require 'auth/operations/customers/set_role'
require 'auth/operations/customers/reconcile_role_index'
require 'onetime/cli/customers/shared'

module Onetime
  module CLI
    class CustomersRoleCommand < Command
      desc 'Manage customer roles (promote, demote, list, reconcile)'

      argument :action,
        type: :string,
        required: true,
        desc: 'Action to perform: promote, demote, list, or reconcile'

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

      # reconcile-only options. --apply and --force are ORTHOGONAL on purpose
      # (the org reconcile precedent): the default run writes nothing so it
      # needs no confirmation; an applied run always needs --force (or an
      # interactive 'y').
      option :apply,
        type: :boolean,
        default: false,
        desc: 'reconcile: write the repair (default: dry-run report)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'reconcile: output as JSON'

      # Valid roles in hierarchy order (highest to lowest). Single source of
      # truth lives on the op; the CLI references it rather than forking a copy.
      VALID_ROLES = Auth::Operations::Customers::SetRole::VALID_ROLES

      def call(action:, email: nil, role: 'colonel', reason: nil, force: false, apply: false, json: false, **)
        boot_application!

        case action.downcase
        when 'promote'
          promote_customer(email, role, force, reason)
        when 'demote'
          demote_customer(email, force, reason)
        when 'list'
          list_customers_by_role(role)
        when 'reconcile'
          reconcile_role_index(apply: apply, force: force, json: json)
        else
          puts "Unknown action: #{action}"
          puts 'Valid actions: promote, demote, list, reconcile'
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

        Auth::Operations::Customers::SetRole.new(
          customer: customer,
          role: target_role,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        ).call

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

        Auth::Operations::Customers::SetRole.new(
          customer: customer,
          role: 'customer',
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        ).call

        puts "#{obscured}: #{old_role} -> customer"
        OT.info "[role-change] #{customer.objid} demoted: #{old_role} -> customer"
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

      # Reconcile customer:role_index:* against the authoritative `role` field
      # (#3974). The index drifts through two familia-2.12 mechanisms — the
      # ADD-ONLY multi_index maintenance on targeted writers (save_fields et
      # al. never clear the previous value's bucket) and customer hashes whose
      # right-to-be-forgotten TTL expired while their index members persist.
      # See the ReconcileRoleIndex op for the full mechanism; this method owns
      # only confirmation, output and exit codes.
      #
      # Default is a report-only dry run. Applying requires --apply plus
      # either --force or an interactive 'y'; a scripted --json apply without
      # --force is refused outright (never mutate from a script that did not
      # say so — the org reconcile rule).
      def reconcile_role_index(apply:, force:, json:)
        return unless confirm_reconcile!(apply: apply, force: force, json: json)

        result = Auth::Operations::Customers::ReconcileRoleIndex.new(
          apply: apply,
          # Never fabricate a Customer for the shell (ADR-023) — the audit
          # trail records the shared CLI sentinel. Only attributed when the
          # run can actually mutate.
          actor: apply ? Customers::Shared::CLI_ACTOR : nil,
        ).call

        OT.info "[cli-customers-role-reconcile] status=#{result.status} " \
                "scanned=#{result.scanned} additions=#{result.additions.size} " \
                "removals=#{result.removals.size} skipped=#{result.skipped.size} " \
                "dry_run=#{result.dry_run}"

        json ? reconcile_output_json(result) : reconcile_output_text(result)

        # A dry run that FOUND drift exits non-zero so scripts and monitoring
        # can detect it (customers doctor precedent); a clean or repaired run
        # exits zero.
        exit 1 if result.status == :drift
      rescue StandardError => ex
        OT.le "[cli-customers-role-reconcile] failed: #{ex.class}: #{ex.message}"
        if json
          puts JSON.pretty_generate(error: "#{ex.class}: #{ex.message}")
        else
          puts "Error: reconcile failed: #{ex.message}"
        end
        exit 1
      end

      # @return [Boolean] true to proceed
      def confirm_reconcile!(apply:, force:, json:)
        return true unless apply
        return true if force

        if json
          puts JSON.pretty_generate(error: 'Refusing to apply without --force in --json mode')
          exit 1
        end

        print 'Apply role-index repairs? [y/N] '
        response = $stdin.gets&.strip&.downcase
        return true if response == 'y'

        puts 'Aborted.'
        false
      end

      def reconcile_output_text(result)
        puts 'DRY RUN — nothing was written' if result.dry_run
        puts "Customers scanned: #{result.scanned}"
        puts "Status:            #{result.status}"

        if result.buckets.any?
          puts
          puts format('%-20s %8s %8s %8s', 'Bucket', 'Members', 'Stale', 'Missing')
          result.buckets.each do |role, stats|
            puts format('%-20s %8d %8d %8d', role, stats[:members], stats[:stale], stats[:missing])
          end
        end

        return if result.status == :clean

        puts
        verb = result.dry_run ? 'Would remove' : 'Removed'
        result.removals.each { |entry| puts "#{verb} #{entry[:objid]} from role_index:#{entry[:role]}" }
        verb = result.dry_run ? 'Would add' : 'Added'
        result.additions.each { |entry| puts "#{verb} #{entry[:objid]} to role_index:#{entry[:role]}" }

        # Entries whose premise no longer held when the applied run revalidated
        # them (concurrent role change) — nothing was written; rerun to
        # re-evaluate from fresh snapshots.
        result.skipped.each do |entry|
          puts "Skipped #{entry[:action]} of #{entry[:objid]} in role_index:#{entry[:role]} (#{entry[:reason]})"
        end
        if result.skipped.any?
          puts
          puts "#{result.skipped.size} entr#{result.skipped.size == 1 ? 'y' : 'ies'} skipped after revalidation; rerun reconcile to re-check."
        end

        return unless result.dry_run

        puts
        puts 'To apply these repairs, run with --apply'
      end

      def reconcile_output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          dry_run: result.dry_run,
          scanned: result.scanned,
          buckets: result.buckets,
          additions: result.additions,
          removals: result.removals,
          skipped: result.skipped,
        )
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
