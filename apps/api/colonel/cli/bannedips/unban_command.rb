# apps/api/colonel/cli/bannedips/unban_command.rb
#
# frozen_string_literal: true

# Remove an IP ban from the shell.
#
# Thin adapter over {Onetime::Operations::UnbanIP} (the single, audited unban
# verb). Unbans are recorded in the admin audit trail with actor `cli`.
#
# Usage:
#   bin/ots bannedips unban 203.0.113.4
#   bin/ots bannedips unban 203.0.113.0/24

require 'onetime/operations/unban_ip'

module Onetime
  module CLI
    class BannedIpsUnbanCommand < Command
      # See BannedIpsBanCommand::CLI_ACTOR — the CLI's non-secret audit sentinel.
      CLI_ACTOR = 'cli'

      desc 'Remove an IP address / CIDR ban'

      argument :ip_address,
        type: :string,
        required: true,
        desc: 'IP address or CIDR range to unban'

      def call(ip_address:, **)
        boot_application!

        ip = ip_address.to_s.strip
        if ip.empty?
          warn 'Error: IP address is required'
          exit 1
        end

        result = Onetime::Operations::UnbanIP.new(
          ip_address: ip,
          actor: CLI_ACTOR,
        ).call

        case result.status
        when :not_found
          puts "Not banned: #{ip}"
        when :success
          puts "Unbanned: #{ip}"
        end
      end
    end

    register 'bannedips unban', BannedIpsUnbanCommand
  end
end
