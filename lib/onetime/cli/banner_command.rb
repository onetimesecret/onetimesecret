# lib/onetime/cli/banner_command.rb
#
# frozen_string_literal: true

# CLI command group for managing the global broadcast banner.
#
# Usage:
#   bin/ots banner                        # Show usage
#   bin/ots banner show                   # Show current banner
#   bin/ots banner set "message"          # Dry-run preview (default)
#   bin/ots banner set "message" --apply  # Write to Redis + refresh runtime
#   bin/ots banner clear                  # Dry-run (default)
#   bin/ots banner clear --apply          # Remove from Redis + refresh runtime

module Onetime
  module CLI
    class BannerCommand < Command
      desc 'Manage the global broadcast banner'

      def call(**)
        boot_application!

        banner = Familia.dbclient(0).get('global_banner')

        if banner && !banner.empty?
          puts format('Current banner: %s', banner)
        else
          puts 'No banner is currently set.'
        end

        puts
        puts 'Usage:'
        puts '  bin/ots banner show                        # Show current banner and TTL'
        puts '  bin/ots banner set "message"               # Dry-run preview (safe default)'
        puts '  bin/ots banner set "message" --apply       # Write to Redis + refresh runtime'
        puts '  bin/ots banner set --file banner.html      # Read content from file'
        puts '  bin/ots banner set --file -                # Read content from stdin'
        puts '  bin/ots banner set "msg" --ttl 3600        # Auto-expire after 1 hour'
        puts '  bin/ots banner clear                       # Dry-run (safe default)'
        puts '  bin/ots banner clear --apply               # Remove banner'
        puts
        puts 'Notes:'
        puts '  Dry-run is the default. Pass --apply to actually write.'
        puts '  Content is HTML-sanitized by the frontend (<a> tags only).'
        puts '  Branded surfaces with displayGlobalBroadcast=false hide the banner.'
      end
    end

    register 'banner', BannerCommand
  end
end
