# lib/onetime/cli/migrate.rb

module Onetime
  class CLI < Drydock::Command
    def migrate
      migration_file = argv.first

      unless migration_file
        puts "Usage: ots migrate MIGRATION_SCRIPT [--run]"
        puts "  --run    Actually apply changes (default is dry run mode)"
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
        puts success ? "\nMigration completed successfully" : "\nMigration failed"
        exit(success ? 0 : 1)
      rescue LoadError => e
        puts "Error loading migration: #{e.message}"
        exit 1
      rescue StandardError => e
        puts "Migration error: #{e.message}"
        puts e.backtrace if OT.debug?
        exit 1
      end
    end

    def move_keys
      sourcedb, targetdb, filter = *argv
      raise 'No target database supplied' unless sourcedb && targetdb
      raise 'No filter supplied' unless filter

      source_uri = URI.parse Familia.uri.to_s
      target_uri = URI.parse Familia.uri.to_s
      source_uri.db = sourcedb
      target_uri.db = targetdb
      Familia::Tools.move_keys filter, source_uri, target_uri do |idx, type, key, ttl|
        if global.verbose > 0
          puts "#{idx + 1.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
        else
          print "\rMoved #{idx + 1} keys"
        end
      end
      puts
    end
  end
end
