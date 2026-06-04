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
        puts 'Run bin/ots domains -h for available subcommands'
      end
    end

    register 'domains', DomainsCommand, aliases: ['domain']
  end
end
