# lib/onetime/cli/sso/audit_email_domains_command.rb
#
# frozen_string_literal: true

# Audit, and on request unlink, a tenant domain's SSO identities whose account
# address lies outside every email domain the organization has proven
# (RISK-2026-10-10-01, #4734).
#
# Usage:
#   bin/ots sso audit-email-domains secrets.example.com                   # Report
#   bin/ots sso audit-email-domains secrets.example.com --unlink          # Preview unlinks
#   bin/ots sso audit-email-domains secrets.example.com --unlink --confirm # Unlink
#   bin/ots sso audit-email-domains secrets.example.com --json            # JSON output
#
# Runbook: docs/runbooks/sso-tenant-email-domain-audit.md

require 'json'

module Onetime
  module CLI
    class SsoAuditEmailDomainsCommand < Command
      desc 'List tenant SSO identities outside the organization\'s proven email domains'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Custom domain display name (secrets.example.com) or CustomDomain extid'

      option :unlink,
        type: :boolean,
        default: false,
        desc: 'Delete the identity rows that fail the check (preview unless --confirm)'

      option :confirm,
        type: :boolean,
        default: false,
        desc: 'Execute changes (WITHOUT this flag the run is forced dry-run)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(domain:, unlink: false, confirm: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!
        require_relative '../../../../apps/web/auth/operations/audit_tenant_email_domains'

        custom_domain = resolve_domain(domain)
        unless custom_domain
          warn "Domain not found: #{domain}"
          exit 1
        end

        dry_run = !confirm
        op      = build_operation(custom_domain, unlink, dry_run, json)
        return unless op

        results = op.call

        if json
          output_json(custom_domain, op, results, dry_run)
        else
          print_header(custom_domain, op, dry_run)
          print_results(results, dry_run, unlink)
          print_next_steps(domain, dry_run, unlink, results)
        end

        exit 1 if results.any? { |r| r.status == :error }
      end

      private

      def resolve_domain(identifier)
        id = identifier.to_s.strip
        Onetime::CustomDomain.load_by_display_domain(id) ||
          Onetime::CustomDomain.find_by_extid(id)
      end

      def build_operation(custom_domain, unlink, dry_run, json)
        Auth::Operations::AuditTenantEmailDomains.new(
          domain: custom_domain,
          unlink: unlink,
          dry_run: dry_run,
        )
      rescue Onetime::Problem => ex
        if json
          puts JSON.generate(error: ex.message)
        else
          warn "Cannot audit: #{ex.message}"
        end
        exit 1
      end

      def print_header(custom_domain, op, dry_run)
        puts "\nTenant SSO Email Domain Audit"
        puts '=' * 60
        puts "  Domain:       #{custom_domain.display_domain}"
        puts "  Organization: #{op.organization.display_name} (#{op.organization.extid})"
        puts "  Provider:     #{op.provider}"
        puts "  Issuer:       #{op.issuer}"
        puts "  Mode:         #{dry_run ? 'DRY RUN' : 'LIVE'}#{op.unlink ? ' (unlink)' : ' (report)'}"
        puts '  WARNING:      SSO config for this domain is DISABLED' unless op.sso_enabled?
      end

      def print_results(results, dry_run, unlink)
        stats = tally(results)

        puts "\nScanned #{results.size} identity row(s) under this issuer"

        if results.any?
          puts
          puts format('  %-26s %-10s %-14s %-28s %s', 'STATUS', 'ACCOUNT', 'CUSTOMER', 'DOMAIN', 'EMAIL')
          puts '  ' + ('-' * 96)
          results.each do |r|
            puts format(
              '  %-26s %-10s %-14s %-28s %s',
              r.status,
              r.account_id,
              r.customer_extid || '-',
              r.asserted_domain || '-',
              r.email_obscured || '-',
            )
          end
        end

        puts "\n" + ('=' * 60)
        puts "Audit #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts format('  %-30s %d', 'Inside proven domains:', stats[:inside])
        puts format('  %-30s %d', 'Outside (bound before #4734):', stats[:outside])
        if unlink
          puts format('  %-30s %d', dry_run ? 'Would unlink:' : 'Unlinked:', stats[:unlink])
        end
        puts format('  %-30s %d', 'Skipped (ambiguous origin):', stats[:ambiguous_origin])
        puts format('  %-30s %d', 'Skipped (no account):', stats[:no_account])

        return if stats[:error].zero?

        puts format('  %-30s %d', 'Errors:', stats[:error])
        results.select { |r| r.status == :error }.each do |r|
          puts "    - account #{r.account_id}: #{r.message}"
        end
      end

      def print_next_steps(domain, dry_run, unlink, results)
        stats = tally(results)

        if !unlink && stats[:outside].positive?
          puts <<~MESSAGE

            #{stats[:outside]} identity row(s) bind this tenant's IdP to an account whose address the
            organization has not proven. Review them, then either have the organization verify
            the email domain under Domains (the rows then report "inside"), or remove the
            bindings:
              bin/ots sso audit-email-domains #{domain} --unlink --confirm
          MESSAGE
        elsif unlink && dry_run && stats[:unlink].positive?
          puts <<~MESSAGE

            Preview only. To delete the #{stats[:unlink]} identity row(s) above:
              bin/ots sso audit-email-domains #{domain} --unlink --confirm
          MESSAGE
        elsif unlink && !dry_run && stats[:unlink].positive?
          puts <<~MESSAGE

            Each unlinked account keeps its address and credentials. To re-admit a legitimate
            user: the organization verifies that email domain under Domains, the user signs in
            on the canonical host (password reset if the account has no password) and links the
            identity again from Connected Identities.
          MESSAGE
        end

        return if stats[:ambiguous_origin].zero?

        puts <<~MESSAGE

          #{stats[:ambiguous_origin]} outside row(s) were left untouched: the account's signup_domain_id does
          not name this domain, so the identity may have been bound by the platform or by
          another tenant that names the same issuer. Review each by hand.
        MESSAGE
      end

      def output_json(custom_domain, op, results, dry_run)
        stats = tally(results)
        puts JSON.pretty_generate(
          domain: custom_domain.display_domain,
          organization: op.organization.extid,
          provider: op.provider,
          issuer: op.issuer,
          sso_enabled: op.sso_enabled?,
          dry_run: dry_run,
          unlink: op.unlink,
          statistics: {
            scanned: results.size,
            inside: stats[:inside],
            outside: stats[:outside],
            unlink: stats[:unlink],
            skipped_ambiguous_origin: stats[:ambiguous_origin],
            skipped_no_account: stats[:no_account],
            errors: stats[:error],
          },
          results: results.map do |r|
            {
              status: r.status,
              account_id: r.account_id,
              uid: r.uid,
              customer: r.customer_extid,
              email: r.email_obscured,
              asserted_domain: r.asserted_domain,
              provider: r.provider,
              issuer: r.issuer,
              organization: r.organization_extid,
              message: r.message,
            }
          end,
        )
      end

      def tally(results)
        stats = { inside: 0, outside: 0, unlink: 0, ambiguous_origin: 0, no_account: 0, error: 0 }
        results.each do |r|
          case r.status
          when :inside                    then stats[:inside]           += 1
          when :outside                   then stats[:outside]          += 1
          when :would_unlink, :unlinked   then stats[:unlink]           += 1
          when :skipped_ambiguous_origin  then stats[:ambiguous_origin] += 1
          when :skipped_no_account        then stats[:no_account]       += 1
          when :error                     then stats[:error]            += 1
          end
        end
        stats
      end

      def show_usage_help
        puts <<~USAGE

          Tenant SSO Email Domain Audit

          Usage:
            bin/ots sso audit-email-domains DOMAIN [options]

          Description:
            Since #4734 tenant SSO creates an account only for an address inside a
            custom domain the organization has proven by TXT ownership check. An
            identity bound to an account before that gate existed keeps signing in
            (hooks/login.rb records it as omniauth_tenant_email_domain_unverified,
            outcome signed_in). That event lists only the accounts that sign in
            again; this command walks the identity rows under the domain's own
            provider route and issuer and reports every one whose account address
            lies outside the proven set.

            With --unlink --confirm the failing rows are deleted. Nothing else
            changes: the account and its Customer stay, the address owner can still
            claim the account through a canonical-host password reset, and the
            tenant identity can no longer sign in to it (a new tenant sign-in for
            that address is refused because the account already exists).

            A row is unlinked ONLY when the account's signup_domain_id names this
            domain. For oidc and entra_id the identity key is shared by every tenant
            and platform configuration that names the same IdP, so any other
            outside row is reported as "skipped (ambiguous origin)" and left for
            manual review.

          Arguments:
            DOMAIN                  Display name (secrets.example.com) or CustomDomain extid

          Options:
            --unlink                Delete the failing identity rows (preview unless --confirm)
            --confirm               Execute changes (default is dry-run)
            --json                  JSON output (for scripting)
            --help, -h              Show this help message

          Examples:
            # Report
            bin/ots sso audit-email-domains secrets.example.com

            # Preview what --unlink would delete
            bin/ots sso audit-email-domains secrets.example.com --unlink

            # Delete the failing rows
            bin/ots sso audit-email-domains secrets.example.com --unlink --confirm

          Safety:
            - Default mode is dry-run (no changes) even without --confirm
            - Idempotent: safe to run multiple times
            - Deletes identity rows only; never an account, Customer or membership
            - Exits 1 when any row reports an error

        USAGE
        true
      end
    end

    register 'sso audit-email-domains', SsoAuditEmailDomainsCommand
  end
end
