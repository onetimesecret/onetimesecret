# lib/onetime/cli/banner_command.rb
#
# frozen_string_literal: true

# CLI command group for managing the global broadcast banner.
#
# The global_banner key in Redis DB 0 is read by the
# CheckGlobalBanner initializer at boot and surfaced by the
# GlobalBroadcast.vue component. The frontend sanitizes content
# to <a> tags only (href, target, rel, class attributes).
#
# Usage:
#   bin/ots banner                        # Show current banner + usage
#   bin/ots banner show                   # Show current banner, TTL, status
#   bin/ots banner set "message"          # Dry-run preview (safe default)
#   bin/ots banner set "message" --apply  # Write to Redis + refresh runtime
#   bin/ots banner clear                  # Dry-run (safe default)
#   bin/ots banner clear --apply          # Remove from Redis + refresh runtime

require 'onetime/operations/banner'

module Onetime
  module CLI
    class BannerCommand < Command
      desc 'Manage the global broadcast banner'

      include Banner::Shared

      def call(**)
        boot_application!

        # Single implementation: read the current banner through the shared op.
        banner = Onetime::Operations::GetBanner.new.call

        if banner.active
          puts format('Current banner: %s', banner.content)
        else
          puts 'No banner is currently set.'
        end

        puts
        puts 'Usage:'
        puts '  bin/ots banner show                       Show current banner and TTL'
        puts '  bin/ots banner set "message"              Dry-run preview (safe default)'
        puts '  bin/ots banner set "message" --apply      Write to Redis + refresh runtime'
        puts '  bin/ots banner set --file banner.html     Read content from file'
        puts '  bin/ots banner set --file -               Read content from stdin'
        puts '  bin/ots banner set "msg" --ttl 3600       Auto-expire after 1 hour'
        puts '  bin/ots banner clear                      Dry-run (safe default)'
        puts '  bin/ots banner clear --apply              Remove banner'
        puts
        puts 'Dry-run is the default. Pass --apply to actually write.'
        puts 'Content is HTML — the frontend sanitizes to <a> tags only.'
        puts 'Branded surfaces with displayGlobalBroadcast=false hide the banner.'
      end
    end

    register 'banner', BannerCommand
  end
end
