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

        db          = Familia.dbclient(0)
        banner_text = db.get(BANNER_KEY)
        ttl         = db.ttl(BANNER_KEY)

        if json
          display_json(banner_text, ttl)
        else
          display_text(banner_text, ttl)
        end
      end

      private

      def display_json(banner_text, ttl)
        data = {
          key: BANNER_KEY,
          database: 0,
          value: banner_text,
          ttl: ttl.negative? ? nil : ttl,
          active: !banner_text.nil? && !banner_text.empty?,
        }

        puts JSON.pretty_generate(data)
      end

      def display_text(banner_text, ttl)
        if banner_text.nil? || banner_text.empty?
          puts 'No banner is currently set.'
          return
        end

        puts 'Global broadcast banner'
        puts '=' * 60
        puts
        puts format('  %-10s %s', 'Content:', banner_text)
        puts format('  %-10s %d characters', 'Length:', banner_text.length)

        if ttl >= 0
          puts format('  %-10s %d seconds (%s)', 'TTL:', ttl, humanize_seconds(ttl))
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
