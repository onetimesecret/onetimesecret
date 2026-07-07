# lib/onetime/cli/banner/show_command.rb
#
# frozen_string_literal: true

#
# CLI command for displaying the current global broadcast banner.
#
# Usage:
#   bin/ots banner show
#   bin/ots banner show --json
#

require 'json'

# The read is performed by the shared Onetime::Operations::GetBanner op (the
# single implementation of the banner "get" verb; the colonel GET
# /api/colonel/banner endpoint is the other adapter). This command owns only the
# text/JSON formatting. Required explicitly (CLI runs outside the autoloader).
require 'onetime/operations/banner'

module Onetime
  module CLI
    class BannerShowCommand < Command
      desc 'Show the current global broadcast banner'

      include Banner::Shared

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(json: false, **)
        boot_application!

        # GetBanner normalises ttl to nil for a persistent/absent banner (Redis's
        # -1/-2 sentinels), matching the display logic below.
        banner = Onetime::Operations::GetBanner.new.call

        if json
          display_json(banner)
        else
          display_text(banner)
        end
      end

      private

      def display_json(banner)
        data = {
          key: banner.key,
          database: banner.database,
          value: banner.content,
          ttl: banner.ttl,
          active: banner.active,
        }

        puts JSON.pretty_generate(data)
      end

      def display_text(banner)
        unless banner.active
          puts 'No banner is currently set.'
          return
        end

        puts 'Global broadcast banner'
        puts '=' * 60
        puts
        puts format('  %-10s %s', 'Content:', banner.content)
        puts format('  %-10s %d characters', 'Length:', banner.content.length)

        if banner.ttl
          puts format('  %-10s %d seconds (%s)', 'TTL:', banner.ttl, humanize_seconds(banner.ttl))
        else
          puts format('  %-10s none (persistent)', 'TTL:')
        end

        puts
        puts 'Note: branded surfaces with displayGlobalBroadcast=false'
        puts 'hide the banner regardless of this key.'
      end
    end

    register 'banner show', BannerShowCommand
  end
end
