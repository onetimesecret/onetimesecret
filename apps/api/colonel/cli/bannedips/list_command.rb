# apps/api/colonel/cli/bannedips/list_command.rb
#
# frozen_string_literal: true

# List banned IP addresses from the shell (read-only — no audit).
#
# Mirrors ColonelAPI::Logic::Colonel::ListBannedIPs: a bounded index read
# (Onetime::BannedIP.instances → load_multi), never a blocking KEYS/SCAN
# (#2211). Sorted most-recently-banned first.
#
# Usage:
#   bin/ots bannedips list

require 'colonel/models/banned_ip'

module Onetime
  module CLI
    class BannedIpsListCommand < Command
      desc 'List banned IP addresses (most recent first)'

      def call(**)
        boot_application!

        ids    = Onetime::BannedIP.instances.to_a
        banned = Onetime::BannedIP.load_multi(ids).compact
        banned.select!(&:ip_address) # drop incomplete/corrupted records
        banned.sort_by! { |ip| -(ip.banned_at || 0) }

        if banned.empty?
          puts 'No IPs are currently banned.'
          return
        end

        puts format('%-24s %-30s %-20s %s', 'IP ADDRESS', 'REASON', 'BANNED AT', 'BANNED BY')
        puts '-' * 96
        banned.each do |ip|
          puts format(
            '%-24s %-30s %-20s %s',
            ip.ip_address,
            truncate(ip.reason, 30),
            format_time(ip.banned_at),
            ip.banned_by || '-',
          )
        end
        puts
        puts "Total: #{banned.size} banned IP(s)"
      end

      private

      def truncate(value, width)
        str = value.to_s
        str = '-' if str.empty?
        str.length > width ? "#{str[0, width - 1]}…" : str
      end

      def format_time(epoch)
        return '-' unless epoch

        Time.at(epoch.to_i).utc.strftime('%Y-%m-%d %H:%M UTC')
      end
    end

    register 'bannedips list', BannedIpsListCommand
  end
end
