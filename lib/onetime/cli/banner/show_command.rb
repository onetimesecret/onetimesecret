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

module Onetime
  module CLI
    module Banner
      class ShowCommand < Command
        desc 'Show the current global broadcast banner'

        option :json,
          type: :boolean,
          default: false,
          desc: 'Output as JSON'

        def call(json: false, **)
          boot_application!

          db = Familia.dbclient(0)
          banner_text = db.get('global_banner')
          ttl = db.ttl('global_banner')

          if json
            display_json(banner_text, ttl)
          else
            display_text(banner_text, ttl)
          end
        end

        private

        def display_json(banner_text, ttl)
          require 'json'

          data = {
            key: 'global_banner',
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
          puts "  Content:  #{banner_text}"
          puts "  Length:   #{banner_text.length} characters"

          if ttl >= 0
            puts format('  TTL:      %d seconds (%s)', ttl, humanize_seconds(ttl))
          else
            puts '  TTL:      none (persistent)'
          end

          puts
          puts 'Note: branded surfaces with displayGlobalBroadcast=false'
          puts 'hide the banner regardless of this key.'
        end

        def humanize_seconds(seconds)
          if seconds >= 86_400
            format('%dd %dh', seconds / 86_400, (seconds % 86_400) / 3600)
          elsif seconds >= 3600
            format('%dh %dm', seconds / 3600, (seconds % 3600) / 60)
          elsif seconds >= 60
            format('%dm %ds', seconds / 60, seconds % 60)
          else
            format('%ds', seconds)
          end
        end
      end
    end

    register 'banner show', Banner::ShowCommand
  end
end
