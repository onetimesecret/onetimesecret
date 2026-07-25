# lib/onetime/cli/customers/change_email_command.rb
#
# frozen_string_literal: true

# Change a customer's account email address (operator remediation).
#
# Usage:
#   bin/ots customers change-email user@old.com user@new.com                  # PREVIEW (default)
#   bin/ots customers change-email ur123abc user@new.com --apply --yes        # execute
#   bin/ots customers change-email 123 user@new.com --apply -y --ticket Z-42  # with provenance
#   bin/ots customers change-email user@old.com user@new.com --json           # machine preview
#
# The cross-store mutation (Rodauth `accounts` row, Customer hash, the global +
# org-scoped email indexes, default-workspace contact_email, pending self-service
# change markers, session revocation, verification reset) AND the single
# AdminAuditEvent are all owned by Auth::Operations::Customers::ChangeEmail — the
# one implementation. The colonel `POST /users/:user_id/email` endpoint is the
# other adapter. This command owns only CLI concerns: resolution, flags, the
# confirmation prompt, rendering, exit codes. It NEVER audits.
#
# PREVIEW IS THE DEFAULT. This is the single highest-value account-takeover
# primitive an operator has, so it follows the Operations::Domains::Remove
# doctrine: no mutation without an explicit `--apply`.
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

module Onetime
  module CLI
    class CustomersChangeEmailCommand < Command
      include Customers::Shared

      desc "Change a customer's account email across every store keyed on it"

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'
      argument :new_email,
        type: :string,
        required: true,
        desc: 'New account email address'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Execute the change (without this the command only previews)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Explicitly preview only (the default; refuses to combine with --apply)'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt (only meaningful with --apply)'
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
      def call(identifier:, new_email:, apply: false, dry_run: false, yes: false, json: false,
               reason: nil, ticket: nil, notify: true, keep_verified: false,
               revoke_sessions: true, allow_closed_account_reuse: false, **)
        boot_application!

        if apply && dry_run
          error_exit('--apply and --dry-run are contradictory; pass one or neither', json: json)
        end

        customer  = resolve_target(identifier, json: json)
        new_email = OT::Utils.normalize_email(new_email)

        # Fail fast, before the prompt. Deliberately the SAME predicate the op
        # uses (format-only, no DNS) so the pre-check and the op cannot disagree
        # and produce a "confirmed then rejected" round trip.
        unless Onetime::Utils::EmailFormat.valid_format?(new_email)
          error_exit("Invalid email address: #{new_email}", json: json)
        end

        confirm!(customer, new_email, json: json) if apply && !yes

        result = Auth::Operations::Customers::ChangeEmail.new(
          customer: customer,
          new_email: new_email,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: !apply,
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
      # :partial — exits non-zero.
      SUCCESS_STATUSES = [:planned, :success, :no_change].freeze

      private

      def confirm!(customer, new_email, json:)
        if json
          error_exit('Refusing to change email without --yes in --json mode', json: true)
        end

        print "Change email for #{customer.obscure_email} (#{customer.extid}) to #{new_email}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        return if response == 'y'

        puts 'Aborted.'
        exit 0
      end

      # rubocop:disable Metrics/MethodLength
      def output_text(result, customer)
        old_display = OT::Utils.obscure_email(result.from.to_s)

        case result.status
        when :planned
          puts 'PREVIEW (nothing changed). Re-run with --apply to execute.'
          puts "  customer:   #{customer.extid} #{old_display}"
          puts "  new email:  #{result.to}"
          puts "  orgs to reindex: #{result.orgs_reindexed}"
        when :success
          puts "Changed #{customer.extid}: #{old_display} -> #{result.to}"
          puts "  auth row updated:   #{result.auth_row_updated}"
          puts "  orgs reindexed:     #{result.orgs_reindexed}"
          puts "  sessions revoked:   #{result.sessions_revoked}"
          puts "  verification reset: #{result.verification_reset}"
        when :no_change
          puts "#{customer.extid} already uses #{result.to}"
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
