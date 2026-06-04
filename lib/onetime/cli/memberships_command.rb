# lib/onetime/cli/memberships_command.rb
#
# frozen_string_literal: true

# CLI command for managing organization membership records. Shows count and usage
# when invoked without a subcommand.
#
# Usage:
#   bin/ots memberships                         # Show count and usage
#   bin/ots memberships doctor --all            # Check all memberships
#   bin/ots memberships doctor --org EXTID      # Check memberships for one org
#

module Onetime
  module CLI
    class MembershipsCommand < Command
      desc 'Manage organization membership records'

      def call(**)
        boot_application!

        active_count  = Onetime::Organization.instances.sum do |objid|
          org = Onetime::Organization.load(objid)
          org ? org.members.size : 0
        end
        pending_count = Onetime::OrganizationMembership.token_lookup.size

        puts format('%d active memberships, %d pending invitations', active_count, pending_count)
        puts
        puts 'Usage:'
        puts '  bin/ots memberships doctor --all            # Check all memberships'
        puts '  bin/ots memberships doctor --org EXTID      # Check memberships for one org'
        puts '  bin/ots memberships doctor --all --repair   # Auto-repair issues'
        puts '  bin/ots memberships doctor --all --json     # JSON output'
        puts
        puts 'Integrity checks:'
        puts '  1. organization_objid points to existing org (CRITICAL)'
        puts '  2. customer_objid points to existing customer (HIGH)'
        puts '  3. org.members entries have backing customer objects (MEDIUM)'
        puts '  4. token_lookup entries are pending memberships (MEDIUM)'
        puts '  5. pending_invitations count matches actual (WARNING)'
        puts '  6. domain_scope_id points to existing domain (WARNING)'
      end
    end

    register 'memberships', MembershipsCommand, aliases: ['membership']
  end
end
