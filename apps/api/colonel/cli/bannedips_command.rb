# apps/api/colonel/cli/bannedips_command.rb
#
# frozen_string_literal: true

# CLI command group for managing banned IP addresses.
#
# Surfaces the ban/unban verbs — previously API-only — on the shell so an
# incident responder can ban an abusive IP without the admin UI (epic #33). All
# subcommands are thin adapters over the single, audited operations
# {Onetime::Operations::BanIP} / {Onetime::Operations::UnbanIP}.
#
# Auto-discovered by lib/onetime/cli.rb's apps/*/*/cli glob — no central require.
#
# Usage:
#   bin/ots bannedips                       # Show count + usage
#   bin/ots bannedips list                  # List banned IPs (most recent first)
#   bin/ots bannedips ban IP [--reason R]   # Ban an IP address / CIDR
#   bin/ots bannedips unban IP              # Remove a ban

require 'colonel/models/banned_ip'

module Onetime
  module CLI
    class BannedIpsCommand < Command
      desc 'Manage banned IP addresses'

      def call(**)
        boot_application!

        count = Onetime::BannedIP.instances.size

        puts format('%d banned IP(s)', count)
        puts
        puts 'Usage:'
        puts '  bin/ots bannedips list                      # List banned IPs (recent first)'
        puts '  bin/ots bannedips ban IP                    # Ban an IP address / CIDR'
        puts '  bin/ots bannedips ban IP --reason "abuse"   # Ban with a reason (stored + audited)'
        puts "  bin/ots bannedips ban IP --expiration 3600  # Auto-expire the ban after 1 hour"
        puts '  bin/ots bannedips unban IP                  # Remove a ban'
        puts
        puts 'Mutations are recorded in the admin audit trail (actor: cli).'
      end
    end

    register 'bannedips', BannedIpsCommand, aliases: ['banned-ips']
  end
end
