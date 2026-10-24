# lib/onetime/cli/customers/change_email_command.rb
#
# frozen_string_literal: true

# Change a customer's account email address (operator remediation).
#
# Usage:
#   bin/ots customers change-email user@old.com user@new.com                  # dry run (default)
#   bin/ots customers change-email ur123abc user@new.com --apply              # execute
#   bin/ots customers change-email 123 user@new.com --apply --ticket Z-42     # with provenance
#   bin/ots customers change-email user@old.com user@new.com --json           # machine preview
#
# The cross-store mutation (Rodauth `accounts` row, Customer hash, the global +
# org-scoped email indexes, default-workspace contact_email, pending self-service
# change markers, session revocation, verification reset) AND the single
# ColonelAuditEvent are all owned by Auth::Operations::Customers::ChangeEmail — the
# one implementation. The colonel `POST /users/:user_id/email` endpoint is the
# other adapter. This command owns only CLI concerns: resolution, flags,
# rendering, exit codes. It NEVER audits.
#
# DRY RUN IS THE DEFAULT (WriteGate). This is the single highest-value
# account-takeover primitive an operator has: no mutation without an explicit
# `--apply`. There is no confirmation prompt. Unlike the other gated verbs,
# `--yes`/`-y`/`-f` are NOT aliases of --apply here: they were a prompt skip
# that also needed --apply, so a bare `--yes` was a preview. They stay as a
# no-op, so `--yes` alone still previews and `--apply --yes` still executes.
#
# NOT gated by SSO-only mode (D37). `require_non_sso_only!` is an API-surface
# concern; gating the shell would remove support's only remediation tool for
# exactly the accounts most likely to need it (an operator changing the address
# on an IdP-owned account is making an informed out-of-band decision — the IdP
# may re-assert its own address on next login, which is why the preview names
# the account).
#
# The CLI runs outside the auth app's autoloader, so the op is required
# explicitly.
require 'json'
require 'auth/operations/customers/change_email'

# Customers::Shared must exist before `include Customers::Shared` below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../write_gate'

module Onetime
  module CLI
    class CustomersChangeEmailCommand < Command
      include Customers::Shared
      include WriteGate

      desc "Change a customer's account email across every store keyed on it"

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'
      argument :new_email,
        type: :string,
        required: true,
        desc: 'New account email address'

      # aliases: [] — see the header: a bare --yes previewed before the gate.
      write_gate_options 'Execute the change', aliases: []
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'No effect; --apply executes. Accepted so --apply --yes scripts still run'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'
      option :reason,
        type: :string,
        desc: 'Operator reason, recorded in the audit detail'
      option :ticket,
        type: :string,
        desc: 'Support ticket reference, recorded in the audit detail'
      option :notify,
        type: :boolean,
        default: true,
        desc: 'Mail both the old and new address (--no-notify for compromised-account remediation)'
      option :keep_verified,
        type: :boolean,
        default: false,
        desc: 'Do NOT reset verification after the swap (typo fixes; the default resets it)'
      option :revoke_sessions,
        type: :boolean,
        default: true,
        desc: 'Revoke every session for the account (--no-revoke-sessions to keep them)'
      option :allow_closed_account_reuse,
        type: :boolean,
        default: false,
        desc: 'Permit an address held only by a CLOSED Rodauth account'

      # rubocop:disable Metrics/ParameterLists
      def call(identifier:, new_email:, apply: false, dry_run: false, json: false,
               reason: nil, ticket: nil, notify: true, keep_verified: false,
               revoke_sessions: true, allow_closed_account_reuse: false, **)
        boot_application!

        dry_run   = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        customer  = resolve_target(identifier, json: json)
        new_email = OT::Utils.normalize_email(new_email)

        # Fail fast, before the op. Deliberately the SAME predicate the op
        # uses (format-only, no DNS) so the pre-check and the op cannot disagree.
        unless Onetime::Utils::EmailFormat.valid_format?(new_email)
          error_exit("Invalid email address: #{new_email}", json: json)
        end

        result = Auth::Operations::Customers::ChangeEmail.new(
          customer: customer,
          new_email: new_email,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
          require_verification: !keep_verified,
          revoke_sessions: revoke_sessions,
          notify: notify,
          reason: reason,
          ticket: ticket,
          allow_closed_account_reuse: allow_closed_account_reuse,
        ).call

        # Obscured on BOTH sides: this line can reach shipped logs.
        OT.info "[cli-customers-change-email] #{result.extid} status=#{result.status} " \
                "#{OT::Utils.obscure_email(result.from.to_s)} -> #{OT::Utils.obscure_email(result.to.to_s)} " \
                "auth_row=#{result.auth_row_updated} orgs=#{result.orgs_reindexed} " \
                "warnings=#{result.warnings.inspect}"

        json ? output_json(result, customer) : output_text(result, customer)

        exit 1 unless SUCCESS_STATUSES.include?(result.status)
      end
      # rubocop:enable Metrics/ParameterLists

      # Statuses that mean "nothing is wrong": the preview ran, the change
      # landed, or it was already the current address. Everything else — including
      # :partial and :verification_not_reset (the swap landed but the account is
      # still verified on an unproven address) — exits non-zero.
      SUCCESS_STATUSES = [:planned, :success, :no_change].freeze

      private

      # rubocop:disable Metrics/MethodLength
      def output_text(result, customer)
        old_display = OT::Utils.obscure_email(result.from.to_s)

        case result.status
        when :planned
          dry_run_header
          puts "  customer:   #{customer.extid} #{old_display}"
          puts "  new email:  #{result.to}"
          puts "  orgs to reindex: #{result.orgs_reindexed}"
          dry_run_footer('execute')
        when :success
          puts "Changed #{customer.extid}: #{old_display} -> #{result.to}"
          puts "  auth row updated:   #{result.auth_row_updated}"
          puts "  orgs reindexed:     #{result.orgs_reindexed}"
          puts "  sessions revoked:   #{result.sessions_revoked}"
          puts "  verification reset: #{result.verification_reset}"
        when :no_change
          puts "#{customer.extid} already uses #{result.to}"
        when :verification_not_reset
          print_verification_not_reset(result, customer)
        when :partial
          print_partial(result, customer)
        when :email_taken
          puts "Error: #{result.to} is already in use by another account."
          puts '       If the address is held only by a CLOSED account, re-run with ' \
               '--allow-closed-account-reuse.'
        when :invalid_email
          puts "Error: Invalid email address: #{result.to}"
        when :not_found
          puts 'Error: Customer has no usable email address (anonymous or empty).'
        else
          puts "Error: Unexpected status #{result.status}"
        end

        print_warnings(result)
      end
      # rubocop:enable Metrics/MethodLength

      # The swap LANDED but the account is still flagged verified on an address
      # nobody has proven ownership of. Distinct from :partial (the stores agree
      # here) and it must not read as success — the operator has to clear the flag
      # by hand before the account is safe to leave alone.
      def print_verification_not_reset(result, customer)
        puts '!! The email changed but VERIFICATION WAS NOT RESET.'
        puts "   customer: #{customer.extid} #{OT::Utils.obscure_email(result.from.to_s)} -> #{result.to}"
        puts '   The account is still marked verified on an address nobody has proven they own.'
        puts "   Run `bin/ots customers unverify #{result.extid}` now, then investigate the warnings below."
      end

      # :partial means the SQL side committed and the Redis side did not finish.
      # It must never read as success — it is the one outcome that leaves the two
      # authoritative stores disagreeing, and the operator has to act.
      def print_partial(result, customer)
        puts '!! PARTIAL — the change did NOT complete. The two stores may disagree.'
        puts "   customer: #{customer.extid} #{OT::Utils.obscure_email(result.from.to_s)} -> #{result.to}"
        puts "   auth (SQL) row now holds the NEW address: #{result.auth_row_updated}"
        puts '   Run `bin/ots customers doctor` — the :auth_email_drift check reports and repairs this.'
      end

      def print_warnings(result)
        warnings = Array(result.warnings)
        return if warnings.empty?

        puts 'Warnings:'
        warnings.each { |warning| puts "  - #{warning}" }
      end

      def output_json(result, customer)
        puts JSON.pretty_generate(
          status: result.status,
          extid: result.extid,
          email: customer.obscure_email,
          from: OT::Utils.obscure_email(result.from.to_s),
          to: result.to,
          dry_run: result.dry_run,
          auth_row_updated: result.auth_row_updated,
          orgs_reindexed: result.orgs_reindexed,
          sessions_revoked: result.sessions_revoked,
          verification_reset: result.verification_reset,
          warnings: result.warnings,
        )
      end

      # Resolve to a mutable, non-anonymous Customer or exit non-zero with a
      # json-aware error. resolve_customer is the shared identifier resolver
      # (email / extid / numeric Rodauth account id).
      def resolve_target(identifier, json:)
        error_exit('Identifier is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot change email on anonymous customer', json: json) if customer.anonymous?

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

    register 'customers change-email', CustomersChangeEmailCommand
  end
end
