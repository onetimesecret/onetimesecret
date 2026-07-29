# lib/onetime/cli/domains_command.rb
#
# frozen_string_literal: true

# CLI command for managing custom domain records. Shows subcommands when
# invoked without arguments.
#
# Usage:
#   bin/ots domains              # Show subcommands
#   bin/ots domains list         # List all domains with filtering options
#   bin/ots domains info DOMAIN  # Show domain details
#   bin/ots domains doctor --all # Check all domains
#

module Onetime
  module CLI
    class DomainsCommand < Command
      desc 'Manage custom domain records'

      def call(**)
        boot_application!

        domain_count = Onetime::CustomDomain.instances.size
        index_count  = Onetime::CustomDomain.display_domain_index.size

        puts format('%d custom domains (%d in display_domain_index index)', domain_count, index_count)
        puts
        puts 'Usage:'
        puts '  bin/ots domains list                       # List domains (filters available)'
        puts '  bin/ots domains info DOMAIN                # Show domain details'
        puts '  bin/ots domains create DOMAIN --org EXTID  # Register a domain for an org'
        puts '  bin/ots domains verify DOMAIN              # Run DNS/TLS verification'
        puts '  bin/ots domains probe DOMAIN               # HTTPS/TLS reachability check'
        puts '  bin/ots domains transfer DOMAIN --to-org X # Move a domain between orgs'
        puts '  bin/ots domains remove DOMAIN              # Permanently delete a domain'
        puts '  bin/ots domains orphaned                   # Domains with no organization'
        puts '  bin/ots domains repair DOMAIN --org-id X   # Fix org relationship issues'
        puts '  bin/ots domains doctor --all               # Check all domains'
        puts '  bin/ots domains migrate-sso FQDN           # Bulk-migrate SSO users (dry run)'
        puts '  bin/ots domains migrate-sso FQDN --run     # Bulk-migrate SSO users (execute)'
        puts
        puts 'Run bin/ots domains -h for available subcommands'
      end
    end

    register 'domains', DomainsCommand, aliases: ['domain']
  end
end
