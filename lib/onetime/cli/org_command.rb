# lib/onetime/cli/org_command.rb
#
# frozen_string_literal: true

# CLI command for managing organization records. Shows count and usage when
# invoked without a subcommand.
#
# Usage:
#   bin/ots org                                # Show count and usage
#   bin/ots org doctor EXTID                   # Check single org integrity
#   bin/ots org doctor --all                   # Check all orgs
#

module Onetime
  module CLI
    class OrgCommand < Command
      desc 'Manage organization records'

      def call(**)
        boot_application!

        puts format('%d organizations', Onetime::Organization.instances.size)
        puts
        puts 'Usage:'
        puts '  bin/ots org doctor EXTID           # Check single org integrity'
        puts '  bin/ots org doctor --all           # Check all organizations'
        puts '  bin/ots org doctor --all --repair  # Auto-repair issues'
        puts '  bin/ots org doctor EXTID --json    # JSON output'
        puts
        puts 'Integrity checks:'
        puts '  1. owner_id points to existing customer (CRITICAL)'
        puts '  2. owner_id customer is in members set (HIGH)'
        puts '  3. All members have backing customer objects (MEDIUM)'
        puts '  4. Membership role:owner matches owner_id (WARNING)'
        puts '  5. Organization has at least one member (WARNING)'
      end
    end

    register 'org', OrgCommand, aliases: ['organization']
  end
end
