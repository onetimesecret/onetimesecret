# lib/onetime/cli/banner/clear_command.rb
#
# frozen_string_literal: true

#
# CLI command for clearing the global broadcast banner.
#
# Dry-run is the default — prints the valkey-cli commands it would run.
# Pass --apply to actually delete the key.
#
# Usage:
#   bin/ots banner clear           # dry-run
#   bin/ots banner clear --apply   # delete the key
#

# The actual delete + runtime refresh + audit event is performed by the shared
# Onetime::Operations::ClearBanner op (the single implementation). This command
# owns only CLI concerns (the dry-run text + confirmation output). Required
# explicitly since the CLI runs outside the app autoloader.
require 'onetime/operations/banner'

module Onetime
  module CLI
    class BannerClearCommand < Command
      desc 'Clear the global broadcast banner (dry-run by default)'

      include Banner::Shared

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Actually delete from Redis (default is dry-run)'

      def call(apply: false, **)
        boot_application!

        db          = Familia.dbclient(0)
        banner_text = db.get(BANNER_KEY)

        if banner_text.nil? || banner_text.empty?
          puts 'No banner is currently set. Nothing to clear.'
          return
        end

        puts format('Current banner: %s', banner_text)
        puts

        if apply
          # Single implementation: the op owns the delete, the runtime refresh, and
          # (new) the admin audit event. The empty-banner short-circuit above means
          # the op always finds a banner here and clears it. Output unchanged.
          Onetime::Operations::ClearBanner.new(actor: CLI_ACTOR).call

          puts 'Banner cleared.'
          puts
          puts 'Note: runtime refresh reaches this process only.'
          puts 'Other running processes will pick it up on next boot or re-read.'
        else
          puts 'Would run (re-run with --apply to write):'
          puts '  # DB 0'
          puts "  DEL #{BANNER_KEY}"
          puts '  # then refresh runtime: Onetime::Runtime.update_features(global_banner: nil)'
        end
      end
    end

    register 'banner clear', BannerClearCommand
  end
end
