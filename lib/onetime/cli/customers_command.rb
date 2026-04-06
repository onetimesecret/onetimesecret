# lib/onetime/cli/customers_command.rb
#
# frozen_string_literal: true

# CLI command for managing customer records. Shows count and usage when
# invoked without a subcommand.
#
# Usage:
#   bin/ots customers                         # Show count and usage
#   bin/ots customers list                    # List all customers
#   bin/ots customers create user@example.com # Create customer with default role
#

module Onetime
  module CLI
    class CustomersCommand < Command
      desc 'Manage customer records (create, list, show, purge)'

      def call(**)
        boot_application!

        puts format('%d customers', Onetime::Customer.instances.size)
        puts
        puts 'Usage:'
        puts '  bin/ots customers list                           # List all customers'
        puts '  bin/ots customers list --by-email               # List grouped by email domain'
        puts '  bin/ots customers create EMAIL                   # Create new customer'
        puts '  bin/ots customers create EMAIL --role colonel    # Create admin'
        puts
        puts 'Subcommands:'
        puts '  bin/ots customers role promote EMAIL       # Promote to colonel'
        puts '  bin/ots customers role demote EMAIL        # Demote to customer'
        puts '  bin/ots customers role list                # List all colonels'
        puts '  bin/ots customers show EMAIL               # Show customer details'
        puts '  bin/ots customers dates                    # Count by creation year'
        puts '  bin/ots customers dates --by-age           # Count by age bucket'
        puts '  bin/ots customers dates --refresh          # Force cache rebuild'
        puts '  bin/ots customers purge --older-than 3y    # Dry-run purge preview'
        puts '  bin/ots customers purge --older-than 3y --purge  # Execute purge'
        puts '  bin/ots customers sync-auth-accounts       # Sync to auth DB'
        puts
        puts 'Remote source (pre-migration):'
        puts '  bin/ots customers dates --redis-url redis://host:6379/6'
        puts '  bin/ots customers purge --older-than 5y --redis-url redis://host:6379/6'
      end
    end

    register 'customers', CustomersCommand, aliases: ['customer']
  end
end
