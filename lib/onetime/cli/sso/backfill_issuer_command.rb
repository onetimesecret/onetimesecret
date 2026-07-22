# lib/onetime/cli/sso/backfill_issuer_command.rb
#
# frozen_string_literal: true

# Backfill the authoritative `issuer` onto a tenant domain's legacy SSO identity
# rows (#3840 Phase 1 / #3838 item 5).
#
# Migration 008 backfilled every pre-existing account_identities row to the
# sentinel issuer ''. Tenant callbacks are issuer-exact, so pre-008 tenant SSO
# users are locked out. This command stamps the issuer the live callback resolves
# onto rows whose account belongs to this domain's organization.
#
# Usage:
#   bin/ots sso backfill-issuer secrets.example.com               # Dry run
#   bin/ots sso backfill-issuer secrets.example.com --confirm     # Execute
#   bin/ots sso backfill-issuer secrets.example.com --issuer URL  # Entra override
#   bin/ots sso backfill-issuer secrets.example.com --json        # JSON output
#
# @see https://github.com/onetimesecret/onetimesecret/issues/3840

require 'json'

module Onetime
  module CLI
    class SsoBackfillIssuerCommand < Command
      desc 'Backfill the authoritative issuer onto legacy tenant SSO identities'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Custom domain display name (secrets.example.com) or CustomDomain extid'

      option :issuer,
        type: :string,
        default: nil,
        desc: 'Operator override for the issuer to stamp (required/recommended for Entra)'

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

      def call(domain:, issuer: nil, confirm: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!
        require_relative '../../../../apps/web/auth/operations/backfill_tenant_issuer'

        custom_domain = resolve_domain(domain)
        unless custom_domain
          warn "Domain not found: #{domain}"
          exit 1
        end

        dry_run = !confirm
        op      = build_operation(custom_domain, issuer, dry_run, json)
        return unless op

        results = op.call

        if json
          output_json(custom_domain, op, results, dry_run)
        else
          print_header(custom_domain, op, dry_run)
          print_results(results, dry_run)
          print_next_steps(domain, dry_run, results)
        end
      end

      private

      # Resolve a DOMAIN argument by display_domain first, then by CustomDomain
      # extid (mirrors the memberships-style single-argument resolver).
      def resolve_domain(identifier)
        id = identifier.to_s.strip
        Onetime::CustomDomain.load_by_display_domain(id) ||
          Onetime::CustomDomain.find_by_extid(id)
      end

      def build_operation(custom_domain, issuer, dry_run, json)
        Auth::Operations::BackfillTenantIssuer.new(
          domain: custom_domain,
          issuer: issuer,
          dry_run: dry_run,
        )
      rescue Onetime::Problem => ex
        if json
          puts JSON.generate(error: ex.message)
        else
          warn "Cannot backfill: #{ex.message}"
        end
        exit 1
      end

      def print_header(custom_domain, op, dry_run)
        puts "\nTenant SSO Issuer Backfill"
        puts '=' * 60
        puts "  Domain:       #{custom_domain.display_domain}"
        puts "  Organization: #{op.organization.display_name} (#{op.organization.extid})"
        puts "  Provider:     #{op.provider}"
        puts "  Issuer:       #{op.issuer}"
        puts "  Mode:         #{dry_run ? 'DRY RUN' : 'LIVE'}"
        puts '  WARNING:      SSO config for this domain is DISABLED (backfilling an inactive domain)' unless op.sso_enabled?
      end

      def print_results(results, dry_run)
        stats = tally(results)

        puts "\nScanned #{results.size} legacy identity row(s) with issuer ''"

        if results.any?
          puts
          puts format('  %-22s %-12s %-14s %s', 'STATUS', 'ACCOUNT', 'CUSTOMER', 'EMAIL')
          puts '  ' + ('-' * 70)
          results.each do |r|
            puts format(
              '  %-22s %-12s %-14s %s',
              r.status,
              r.account_id,
              r.customer_extid || '-',
              r.email_obscured || '-',
            )
          end
        end

        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts format('  %-30s %d', dry_run ? 'Would stamp:' : 'Stamped:', stats[:stamp])
        puts format('  %-30s %d', dry_run ? 'Would dedupe:' : 'Deduped:', stats[:dedupe])
        puts format('  %-30s %d', 'Skipped (out of scope):', stats[:out_of_scope])
        puts format('  %-30s %d', 'Skipped (ambiguous origin):', stats[:ambiguous_origin])
        puts format('  %-30s %d', 'Skipped (multiple candidates):', stats[:multiple_candidates])
        puts format('  %-30s %d', 'Skipped (no customer):', stats[:no_customer])

        unless stats[:multiple_candidates].zero?
          puts "\n  Multiple-candidate accounts (>1 legacy '' row on the shared route; stamp one by"
          puts '  hand only after confirming which uid this tenant minted):'
          results.select { |r| r.status == :skipped_multiple_candidates }
            .map(&:account_id).uniq.each do |account_id|
            puts "    - account #{account_id}"
          end
        end

        return if stats[:error].zero?

        puts format('  %-30s %d', 'Errors / conflicts:', stats[:error])
        results.select { |r| r.status == :error }.each do |r|
          puts "    - account #{r.account_id}: #{r.message}"
        end
      end

      def print_next_steps(domain, dry_run, results)
        return unless dry_run

        stats = tally(results)
        return if (stats[:stamp] + stats[:dedupe]).zero?

        puts <<~MESSAGE

          Verify the issuer above against the IdP's published metadata, then run:
            bin/ots sso backfill-issuer #{domain} --confirm
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
          statistics: {
            scanned: results.size,
            stamp: stats[:stamp],
            dedupe: stats[:dedupe],
            skipped_out_of_scope: stats[:out_of_scope],
            skipped_ambiguous_origin: stats[:ambiguous_origin],
            skipped_multiple_candidates: stats[:multiple_candidates],
            skipped_no_customer: stats[:no_customer],
            errors: stats[:error],
          },
          results: results.map do |r|
            {
              status: r.status,
              account_id: r.account_id,
              uid: r.uid,
              customer: r.customer_extid,
              email: r.email_obscured,
              provider: r.provider,
              issuer: r.issuer,
              organization: r.organization_extid,
              message: r.message,
            }
          end,
        )
      end

      def tally(results)
        stats = {
          stamp: 0,
          dedupe: 0,
          out_of_scope: 0,
          ambiguous_origin: 0,
          multiple_candidates: 0,
          no_customer: 0,
          error: 0,
        }
        results.each do |r|
          case r.status
          when :would_stamp, :stamped         then stats[:stamp]               += 1
          when :would_dedupe, :deduped        then stats[:dedupe]              += 1
          when :skipped_out_of_scope          then stats[:out_of_scope]        += 1
          when :skipped_ambiguous_origin      then stats[:ambiguous_origin]    += 1
          when :skipped_multiple_candidates   then stats[:multiple_candidates] += 1
          when :skipped_no_customer           then stats[:no_customer]         += 1
          when :error                         then stats[:error]               += 1
          end
        end
        stats
      end

      def show_usage_help
        puts <<~USAGE

          Tenant SSO Issuer Backfill

          Usage:
            bin/ots sso backfill-issuer DOMAIN [options]

          Description:
            Migration 008 backfilled every pre-existing SSO identity to the sentinel
            issuer ''. Tenant callbacks are issuer-exact, so tenant SSO users who
            existed before 008 are locked out. This command stamps the authoritative
            issuer onto legacy rows whose account belongs to the domain organization,
            so the exact tenant lookup matches again.

            Only oidc and entra_id domains are eligible: google/github resolve to the
            '' sentinel at callback time, so their legacy rows already match.

            Scoping is per-row and fail-closed: a row is stamped ONLY when it passes
            BOTH gates —
              1. domain scope: the account has an active membership permitted to
                 access THIS domain (not another domain in the same org); and
              2. provenance: the account's signup_domain_id matches THIS domain, so
                 the '' row was minted by this tenant's IdP (not the platform or
                 another domain — stamping those would break their login).
            Rows failing either gate are reported (skipped: out of scope / ambiguous
            origin) and left untouched for manual follow-up.

          Arguments:
            DOMAIN                  Display name (secrets.example.com) or CustomDomain extid

          Options:
            --issuer URL            Override the issuer to stamp. REQUIRED/recommended
                                    for Entra, whose live `iss` is
                                    https://login.microsoftonline.com/{tenant_id}/v2.0
            --confirm               Execute changes (default is dry-run)
            --json                  JSON output (for scripting)
            --help, -h              Show this help message

          Examples:
            # Preview (dry run) — prints the exact issuer per affected row
            bin/ots sso backfill-issuer secrets.example.com

            # Execute
            bin/ots sso backfill-issuer secrets.example.com --confirm

            # Entra with explicit issuer override
            bin/ots sso backfill-issuer secrets.example.com \\
              --issuer https://login.microsoftonline.com/TENANT_ID/v2.0 --confirm

          Safety:
            - Default mode is dry-run (no changes) even without --confirm
            - Idempotent: safe to run multiple times
            - Stamps a row ONLY when it passes both gates: (1) the account has an
              active membership scoped to THIS domain, and (2) the account's
              signup_domain_id matches THIS domain; rows failing either are skipped
            - Cross-account conflicts are reported, never auto-resolved

        USAGE
        true
      end
    end

    register 'sso backfill-issuer', SsoBackfillIssuerCommand
  end
end
