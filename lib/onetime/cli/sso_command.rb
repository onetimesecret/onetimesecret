# lib/onetime/cli/sso_command.rb
#
# frozen_string_literal: true

# CLI command group for SSO identity maintenance. Shows a count of legacy
# sentinel-issuer ('') identity rows and usage when invoked without a subcommand.
#
# Usage:
#   bin/ots sso                                  # Show legacy-row count and usage
#   bin/ots sso backfill-issuer DOMAIN           # Backfill tenant issuer (dry run)
#   bin/ots sso backfill-issuer DOMAIN --confirm # Backfill tenant issuer (execute)
#

module Onetime
  module CLI
    class SsoCommand < Command
      desc 'Maintain SSO identity records (issuer backfill)'

      def call(**)
        boot_application!

        legacy_count = count_legacy_identities

        if legacy_count.nil?
          puts 'Auth database unavailable (simple auth mode); no SSO identities to report.'
        else
          puts format('%d legacy identity row(s) with sentinel issuer \'\' across all providers', legacy_count)
        end
        puts
        puts 'Usage:'
        puts '  bin/ots sso backfill-issuer DOMAIN                 # Preview (dry run)'
        puts '  bin/ots sso backfill-issuer DOMAIN --confirm       # Execute'
        puts '  bin/ots sso backfill-issuer DOMAIN --issuer URL    # Override issuer (Entra)'
        puts '  bin/ots sso backfill-issuer DOMAIN --json          # JSON output'
        puts
        puts 'DOMAIN = custom domain display name (e.g. secrets.example.com) or CustomDomain extid.'
        puts
        puts 'What backfill-issuer does (#3840 / #3838 item 5):'
        puts '  Migration 008 backfilled all pre-existing SSO identities to issuer \'\'.'
        puts '  Tenant callbacks are issuer-exact, so pre-008 tenant users are locked out.'
        puts '  This stamps the authoritative issuer onto rows that pass two fail-closed'
        puts '  gates (domain-scoped membership + matching signup_domain_id), so the exact'
        puts '  tenant lookup matches again without touching platform/other-domain rows.'
      end

      private

      def count_legacy_identities
        db = Auth::Database.connection
        return nil unless db

        db[:account_identities].where(issuer: '').count
      rescue StandardError => ex
        OT.le "[sso] Failed to count legacy identities: #{ex.message}"
        nil
      end
    end

    register 'sso', SsoCommand
  end
end
