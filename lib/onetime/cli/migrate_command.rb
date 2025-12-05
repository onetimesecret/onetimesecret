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
              puts "  - #{File.basename(file)}"
            end
          end
          return
        end

        # Check if migration_file is already a full path
        if File.exist?(migration_file)
          migration_path = migration_file
        else
          migration_paths = migration_dirs.map { |dir| File.join(dir, migration_file) }
          migration_path  = migration_paths.find { |path| File.exist?(path) }
        end

        unless migration_path
          puts "Migration script not found: #{migration_file}"
          return
        end

        begin
          # Load the migration script
          require migration_path

          # Run the migration with options
          success = Onetime::Migration.run(run: run)
          if run
            puts success ? 'Migration completed successfully' : 'Migration did not run'
          else
            puts success ? 'Dry run completed successfully' : 'Dry run failed'
          end
          exit(success ? 0 : 1)
        rescue LoadError => ex
          warn "Error loading migration: #{ex.message}"
          exit 1
        rescue StandardError => ex
          warn "Migration error: #{ex.message}"
          warn ex.backtrace if OT.debug?
          exit 1
        end
      end
    end

    register 'migrate', MigrateCommand
  end
end
