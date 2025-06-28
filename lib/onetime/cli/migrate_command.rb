# lib/onetime/cli/migrate_command.rb

module Onetime

  # Migrate Command
  #
  # NOTE: It's important to subclass Onetime::CLI in order to call OT.boot!
  # automatically. Unless you're writing a command that does not want to
  # boot right away, then use Drydock::Command.
  #
  class MigrateCommand < Onetime::CLI
    def migrate
      migration_file = argv.first

      unless migration_file
        puts 'Usage: ots migrate MIGRATION_SCRIPT [--run]'
        puts '  --run    Actually apply changes (default is dry run mode)'
        puts "\nAvailable migrations:"
        Dir[File.join(Onetime::HOME, 'migrate', '*.rb')].each do |file|
          puts "  - #{File.basename(file)}"
        end
        return
      end

      migration_path = File.join(Onetime::HOME, 'migrate', migration_file)
      unless File.exist?(migration_path)
        puts "Migration script not found: #{migration_file}"
        return
      end

      begin
        # Load the migration script
        require_relative migration_path

        # Run the migration with options
        success = Onetime::Migration.run(run: option.run)
        if option.run
          puts success ? "\nMigration completed successfully" : "\nMigration did not run"
        else
          puts success ? "\nDry run completed successfully" : "\nDry run failed"
        end
        exit(success ? 0 : 1)
      rescue LoadError => ex
        puts "Error loading migration: #{ex.message}"
        exit 1
      rescue StandardError => ex
        puts "Migration error: #{ex.message}"
        puts ex.backtrace if OT.debug?
        exit 1
      end
    end
  end
end
