# lib/onetime/cli/migrate_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Migrate command using Familia::Migration infrastructure
    #
    # Usage:
    #   bin/ots migrate                     # Show status of all migrations
    #   bin/ots migrate --status            # Same as above
    #   bin/ots migrate --run               # Run all pending migrations
    #   bin/ots migrate --dry-run           # Preview all pending migrations
    #   bin/ots migrate MIGRATION_ID --run  # Run specific migration
    #   bin/ots migrate --rollback ID       # Rollback specific migration
    #   bin/ots migrate --validate          # Check migration dependencies
    #
    class MigrateCommand < Command
      desc 'Run Familia-based data migrations'

      argument :migration_id,
        type: :string,
        required: false,
        desc: 'Specific migration ID to run (optional)'

      option :run,
        type: :boolean,
        default: false,
        aliases: ['r'],
        desc: 'Actually apply changes (default is dry run mode)'

      option :status,
        type: :boolean,
        default: false,
        aliases: ['s'],
        desc: 'Show migration status'

      option :rollback,
        type: :string,
        default: nil,
        desc: 'Rollback a specific migration by ID'

      option :validate,
        type: :boolean,
        default: false,
        desc: 'Validate migration dependencies'

      option :dir,
        type: :string,
        default: nil,
        aliases: ['d'],
        desc: 'Migration directory to load (default: migrations/)'

      def call(migration_id: nil, run: false, status: false, rollback: nil, validate: false, dir: nil, **)
        boot_application!

        # Load migrations from directory
        migration_dir = dir || default_migration_dir
        load_migrations(migration_dir)

        runner = Familia::Migration::Runner.new

        if validate
          run_validate(runner)
        elsif rollback
          run_rollback(runner, rollback)
        elsif status || (migration_id.nil? && !run)
          show_status(runner)
        elsif migration_id
          run_single_migration(migration_id, run: run)
        else
          run_all_migrations(runner, run: run)
        end
      end

      private

      def default_migration_dir
        # Default to most recent migration directory
        migrations_root = File.join(Onetime::HOME, 'migrations')
        dirs            = Dir.glob(File.join(migrations_root, '20*')).reverse
        dirs.first || migrations_root
      end

      def load_migrations(dir)
        unless Dir.exist?(dir)
          puts "Migration directory not found: #{dir}"
          puts 'Available directories:'
          list_migration_dirs
          exit 1
        end

        # Load helper first if exists
        helper_path = File.join(dir, 'lib', 'migration_helper.rb')
        require helper_path if File.exist?(helper_path)

        # Load all migration files in order
        migration_files  = Dir.glob(File.join(dir, '*_migration.rb'))
        migration_files += Dir.glob(File.join(dir, '*_generator.rb'))

        migration_files.uniq.sort.each do |file|
          require file
        end

        puts "Loaded #{Familia::Migration.migrations.size} migrations from #{dir}"
      end

      def list_migration_dirs
        migrations_root = File.join(Onetime::HOME, 'migrations')
        Dir.glob(File.join(migrations_root, '20*')).reverse_each do |d|
          puts "  - #{File.basename(d)}"
        end
      end

      def show_status(runner)
        puts 'Migration Status'
        puts '=' * 70

        status_list = runner.status
        if status_list.empty?
          puts 'No migrations registered'
          return
        end

        applied_count = 0
        pending_count = 0

        status_list.each do |entry|
          if entry[:status] == :applied
            applied_count += 1
            time_str       = entry[:applied_at]&.strftime('%Y-%m-%d %H:%M') || 'unknown'
            puts "  ✓ Applied    #{entry[:migration_id].to_s.ljust(45)} #{time_str}"
          else
            pending_count += 1
            puts "  ○ Pending    #{entry[:migration_id]}"
          end
        end

        puts '-' * 70
        puts "Total: #{status_list.size} (#{applied_count} applied, #{pending_count} pending)"

        if pending_count > 0 && !options[:run]
          puts
          puts 'Run with --run to apply pending migrations'
        end
      end

      def run_all_migrations(runner, run:)
        mode = run ? 'EXECUTE' : 'DRY RUN'
        puts "Running all pending migrations (#{mode})"
        puts '=' * 70

        results = runner.run(dry_run: !run)

        if results.empty?
          puts 'No pending migrations to run'
          return
        end

        print_results(results)

        success_count = results.count { |r| r[:status] == :success }
        failed_count  = results.count { |r| r[:status] == :failed }

        puts
        puts '=' * 70
        puts "Completed: #{success_count} success, #{failed_count} failed"

        exit 1 if failed_count > 0
      end

      def run_single_migration(migration_id, run:)
        migration_class = Familia::Migration.migrations.find do |m|
          m.migration_id == migration_id || m.name.include?(migration_id)
        end

        unless migration_class
          puts "Migration not found: #{migration_id}"
          puts
          puts 'Available migrations:'
          Familia::Migration.migrations.each do |m|
            puts "  - #{m.migration_id}"
          end
          exit 1
        end

        mode = run ? 'EXECUTE' : 'DRY RUN'
        puts "Running migration: #{migration_class.migration_id} (#{mode})"
        puts '=' * 70

        exit_code = migration_class.cli_run(run ? ['--run'] : [])
        exit exit_code
      end

      def run_rollback(runner, migration_id)
        puts "Rolling back migration: #{migration_id}"
        puts '=' * 70

        result = runner.rollback(migration_id)

        case result[:status]
        when :rolled_back
          puts "✓ Successfully rolled back: #{migration_id}"
          puts "  Restored #{result[:restored_fields] || 0} fields"
        when :not_found
          puts "✗ Migration not found: #{migration_id}"
          exit 1
        when :not_reversible
          puts "✗ Migration is not reversible: #{migration_id}"
          exit 1
        when :failed
          puts "✗ Rollback failed: #{result[:error]}"
          exit 1
        else
          puts "✗ Unknown rollback status: #{result[:status]}"
          exit 1
        end
      end

      def run_validate(runner)
        puts 'Validating migration dependencies...'
        puts '=' * 70

        issues = runner.validate

        if issues.empty?
          puts '✓ All migrations valid'
        else
          puts "Found #{issues.size} issue(s):"
          issues.each do |issue|
            msg = issue[:message] || issue[:dependency] || issue[:migration_id]
            puts "  ✗ #{issue[:type]}: #{msg}"
          end
          exit 1
        end
      end

      def print_results(results)
        results.each do |result|
          status_icon = case result[:status]
                        when :success then '✓'
                        when :skipped then '○'
                        when :failed then '✗'
                        else '?'
                        end

          dry_run_note = result[:dry_run] ? ' (dry run)' : ''
          puts "#{status_icon} #{result[:migration_id]}#{dry_run_note}"

          if result[:error]
            puts "    Error: #{result[:error]}"
          end

          next unless result[:stats]&.any?

          result[:stats].each do |key, value|
            puts "    #{key}: #{value}"
          end
        end
      end
    end

    register 'migrate', MigrateCommand
  end
end
