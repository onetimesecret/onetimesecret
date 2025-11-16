# lib/onetime/cli/migrate_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    class MigrateCommand < Command
      desc 'Run a migration script from the migrate/ directory'

      argument :migration_file, type: :string, required: false, desc: 'Migration script filename'

      option :run, type: :boolean, default: false, aliases: ['r'],
        desc: 'Actually apply changes (default is dry run mode)'

      def call(migration_file: nil, run: false, **)
        boot_application!

        migration_dirs = [
          File.join(Onetime::HOME, 'migrations'),
          File.join(Onetime::HOME, 'migrations', 'core'),
        ]

        unless migration_file
          usage_text = <<~USAGE
            Usage: ots migrate MIGRATION_SCRIPT [--run]
              --run    Actually apply changes (default is dry run mode)

            Available migrations:
          USAGE
          print usage_text

          migration_dirs.each do |dir|
            Dir[File.join(dir, '*.rb')].each do |file|
              OT.li "  - #{File.basename(file)}"
            end
          end
          return
        end

        migration_paths = migration_dirs.map { |dir| File.join(dir, migration_file) }
        migration_path  = migration_paths.find { |path| File.exist?(path) }

        unless migration_path
          OT.li "Migration script not found: #{migration_file}"
          return
        end

        begin
          # Load the migration script
          require_relative migration_path

          # Run the migration with options
          success = Onetime::Migration.run(run: run)
          if run
            OT.li success ? 'Migration completed successfully' : 'Migration did not run'
          else
            OT.li success ? 'Dry run completed successfully' : 'Dry run failed'
          end
          exit(success ? 0 : 1)
        rescue LoadError => ex
          OT.le "Error loading migration: #{ex.message}"
          exit 1
        rescue StandardError => ex
          OT.le "Migration error: #{ex.message}"
          OT.le ex.backtrace if OT.debug?
          exit 1
        end
      end
    end

    register 'migrate', MigrateCommand
  end
end
