# lib/onetime/cli/domains_command.rb
#
# frozen_string_literal: true

# CLI command for managing custom domain records. Shows count and usage when
# invoked without a subcommand.
#
# Usage:
#   bin/ots domains                             # Show count and usage
#   bin/ots domains doctor secrets.example.com  # Check single domain
#   bin/ots domains doctor --all                # Check all domains
#

module Onetime
  module CLI
    class DomainsCommand < Command
      desc 'Manage custom domain records'

      def call(**)
        boot_application!

        domain_count = Onetime::CustomDomain.instances.size
        index_count  = Onetime::CustomDomain.display_domains.size

        puts format('%d custom domains (%d in display_domains index)', domain_count, index_count)
        puts
        puts 'Usage:'
        puts '  bin/ots domains doctor secrets.example.com  # Check single domain'
        puts '  bin/ots domains doctor --all                # Check all domains'
        puts '  bin/ots domains doctor --org EXTID          # Check domains for one org'
        puts '  bin/ots domains doctor --all --repair       # Auto-repair issues'
        puts '  bin/ots domains doctor --all --json         # JSON output'
        puts
        puts 'Integrity checks:'
        puts '  1. org_id points to existing organization (CRITICAL)'
        puts '  2. display_domain field is not empty (HIGH)'
        puts '  3. display_domain_index entries are valid (HIGH)'
        puts '  4. display_domains hash entries are valid (MEDIUM)'
        puts '  5. Domain is in org.domains sorted set (MEDIUM)'
        puts '  6. org.domains entries have valid domain objects (MEDIUM)'
        puts '  7. verification_state is coherent (WARNING)'
        puts '  8. txt_validation_value format is valid (LOW)'
      end
    end

    register 'domains', DomainsCommand, aliases: ['domain']
  end
end
