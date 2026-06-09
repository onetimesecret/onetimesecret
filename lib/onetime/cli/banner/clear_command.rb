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

module Onetime
  module CLI
    module Banner
      class ClearCommand < Command
        desc 'Clear the global broadcast banner (dry-run by default)'

        option :apply,
          type: :boolean,
          default: false,
          desc: 'Actually delete from Redis (default is dry-run)'

        def call(apply: false, **)
          boot_application!

          db = Familia.dbclient(0)
          banner_text = db.get('global_banner')

          if banner_text.nil? || banner_text.empty?
            puts 'No banner is currently set. Nothing to clear.'
            return
          end

          puts format('Current banner: %s', banner_text)
          puts

          if apply
            db.del('global_banner')
            Onetime::Runtime.update_features(global_banner: nil)

            puts 'Banner cleared.'
            puts
            puts 'Note: runtime refresh reaches this process only.'
            puts 'Other running processes will pick it up on next boot or re-read.'
          else
            puts 'Would run (re-run with --apply to write):'
            puts '  # DB 0'
            puts '  DEL global_banner'
            puts '  # then refresh runtime: Onetime::Runtime.update_features(global_banner: nil)'
          end
        end
      end
    end

    register 'banner clear', Banner::ClearCommand
  end
end
