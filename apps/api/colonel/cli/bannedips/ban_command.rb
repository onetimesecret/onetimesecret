# apps/api/colonel/cli/bannedips/ban_command.rb
#
# frozen_string_literal: true

# Ban an IP address / CIDR from the shell.
#
# Thin adapter over {Onetime::Operations::BanIP} (the single, audited ban verb).
# The op is loaded explicitly because CLI runs don't go through the colonel app's
# autoloader. Bans are recorded in the admin audit trail with actor `cli`.
#
# Usage:
#   bin/ots bannedips ban 203.0.113.4
#   bin/ots bannedips ban 203.0.113.0/24 --reason "credential stuffing"
#   bin/ots bannedips ban 203.0.113.4 --expiration 3600   # auto-expire in 1h

require 'ipaddr'
require 'onetime/operations/ban_ip'

module Onetime
  module CLI
    class BannedIpsBanCommand < Command
      # Audit actor recorded for CLI-initiated mutations. The shell carries no
      # authenticated colonel identity; a plain, non-secret public sentinel is
      # used — never an internal objid. Mirrors Customers::Shared::CLI_ACTOR.
      CLI_ACTOR = 'cli'

      desc 'Ban an IP address or CIDR range'

      argument :ip_address,
        type: :string,
        required: true,
        desc: 'IP address or CIDR range to ban (e.g. 203.0.113.4 or 203.0.113.0/24)'

      option :reason,
        type: :string,
        desc: 'Reason for the ban (stored on the record and in the audit trail)'
      option :expiration,
        type: :integer,
        desc: 'Auto-expire the ban after this many seconds (default: permanent)'

      def call(ip_address:, reason: nil, expiration: nil, **)
        boot_application!

        ip = ip_address.to_s.strip
        if ip.empty?
          warn 'Error: IP address is required'
          exit 1
        end

        # Validate format up front, matching the colonel endpoint's guard.
        begin
          IPAddr.new(ip)
        rescue IPAddr::InvalidAddressError
          warn "Error: invalid IP address or CIDR: #{ip}"
          exit 1
        end

        result = Onetime::Operations::BanIP.new(
          ip_address: ip,
          reason: reason,
          banned_by: CLI_ACTOR,
          actor: CLI_ACTOR,
          expiration: expiration,
        ).call

        case result.status
        when :already_banned
          puts "Already banned: #{ip}"
        when :success
          puts "Banned: #{ip}"
          puts "  Reason: #{result.reason}" if result.reason && !result.reason.to_s.empty?
          puts "  Expires: #{expiration ? "in #{expiration}s" : 'never'}"
        end
      end
    end

    register 'bannedips ban', BannedIpsBanCommand
  end
end
