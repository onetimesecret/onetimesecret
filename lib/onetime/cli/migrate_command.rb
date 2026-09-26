# lib/onetime/cli/migrate_command.rb
#
# frozen_string_literal: true

require_relative 'migrate_runner'

module Onetime
  module CLI
    # Migrate command using Familia::Migration infrastructure
    #
    # Usage:
    #   bin/ots migrate                       # Show status of the newest batch
    #   bin/ots migrate --status              # Same as above
    #   bin/ots migrate --dry-run             # Preview all pending migrations
    #   bin/ots migrate --run                 # Apply all pending migrations
    #   bin/ots migrate MIGRATION_ID          # Preview one migration
    #   bin/ots migrate MIGRATION_ID --run    # Apply one migration
    #   bin/ots migrate path/to/file.rb --run # Same, loading only that file
    #   bin/ots migrate --rollback ID         # Preview a rollback
    #   bin/ots migrate --rollback ID --run   # Roll back an applied migration
    #   bin/ots migrate --validate            # Check migration dependencies
    #
    # Every modifying path (batch, single, rollback) goes through
    # MigrateRunner, so it is dependency-checked, runs the full lifecycle,
    # and is recorded in the registry exactly once, only on success.
    # Nothing modifies data without --run.
    #
    class MigrateCommand < Command
      desc 'Run Familia-based data migrations'

      STATUS_ICONS = {
        success: '✓',
        rolled_back: '✓',
        skipped: '○',
        partial: '!',
        failed: '✗',
        already_applied: '✗',
      }.freeze

      argument :migration_id,
        type: :string,
        required: false,
        desc: 'Migration ID or file path to run (optional)'

      option :run,
        type: :boolean,
        default: false,
        aliases: ['r'],
        desc: 'Apply changes (without it, every action is a dry run)'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview without applying changes (the default; explicit form previews all pending)'

      option :status,
        type: :boolean,
        default: false,
        aliases: ['s'],
        desc: 'Show migration status'

      option :rollback,
        type: :string,
        default: nil,
        desc: 'Roll back a specific migration by ID (dry run unless --run)'

      option :validate,
        type: :boolean,
        default: false,
        desc: 'Validate migration dependencies'

      option :dir,
        type: :string,
        default: nil,
        aliases: ['d'],
        desc: 'Migration directory to load (default: newest migrations/20* directory)'

      def call(migration_id: nil, run: false, dry_run: false, status: false, rollback: nil, validate: false, dir: nil, **)
        if run && dry_run
          puts 'Choose one of --run or --dry-run'
          exit 1
        end

        boot_application!

        specific_file = nil

        # If migration_id looks like a file path, extract directory and track the specific file
        if migration_id && migration_id.include?('/')
          specific_file  = File.expand_path(migration_id)
          specific_file += '.rb' unless specific_file.end_with?('.rb')
          dir          ||= File.dirname(specific_file)
          migration_id   = File.basename(migration_id, '.rb')
        end

        # Load migrations from directory (or just the specific file)
        migration_dir = dir || default_migration_dir
        load_migrations(migration_dir, specific_file: specific_file)

        runner = MigrateRunner.new

        if validate
          run_validate(runner)
        elsif status || (rollback.nil? && migration_id.nil? && !run && !dry_run)
          show_status(runner)
        elsif rollback
          run_rollback(runner, rollback, dry_run: !run)
        elsif migration_id
          run_single_migration(runner, migration_id, dry_run: !run, specific_file: specific_file)
        else
          run_all_migrations(runner, dry_run: !run)
        end
      rescue Familia::Migration::Errors::MigrationError => ex
        puts "✗ #{ex.class.name.split('::').last}: #{ex.message}"
        exit 1
      end

      private

      def default_migration_dir
        # Default to most recent migration directory
        migrations_root = File.join(Onetime::HOME, 'migrations')
        dirs            = Dir.glob(File.join(migrations_root, '20*')).reverse
        dirs.first || migrations_root
      end

      def load_migrations(dir, specific_file: nil)
        dir = File.expand_path(dir)
        unless Dir.exist?(dir)
          puts "Migration directory not found: #{dir}"
          puts 'Available directories:'
          list_migration_dirs
          exit 1
        end

        # Load helper first if exists
        helper_path = File.join(dir, 'lib', 'migration_helper.rb')
        require helper_path if File.exist?(helper_path)

        # If a specific file was requested, only load that one
        # (avoids class name collisions in legacy migrations)
        if specific_file
          unless File.exist?(specific_file)
            puts "Migration file not found: #{specific_file}"
            exit 1
          end
          require specific_file
          puts "Loaded migration from #{specific_file}"
          return
        end

        # Load all migration files in order
        # Try specific patterns first, fall back to all .rb files
        migration_files  = Dir.glob(File.join(dir, '*_migration.rb'))
        migration_files += Dir.glob(File.join(dir, '*_generator.rb'))

        # If no specifically-named files found, load all .rb files
        # (Familia::Migration only registers classes that inherit from Base/Pipeline/Model)
        migration_files = Dir.glob(File.join(dir, '*.rb')) if migration_files.empty?

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

        return unless pending_count > 0

        puts
        puts 'Preview with --dry-run; apply with --run'
      end

      def run_all_migrations(runner, dry_run:)
        puts "Running all pending migrations (#{mode_label(dry_run)})"
        puts '=' * 70

        results = runner.run(dry_run: dry_run)

        if results.empty?
          puts 'No pending migrations to run'
          return
        end

        print_results(results)
        finish(results, dry_run: dry_run)
      end

      def run_single_migration(runner, migration_id, dry_run:, specific_file: nil)
        migration_class = find_migration_class(migration_id, specific_file: specific_file)

        puts "Running migration: #{migration_class.migration_id} (#{mode_label(dry_run)})"
        puts '=' * 70

        result = runner.run_one(migration_class, dry_run: dry_run)
        print_results([result])
        finish([result], dry_run: dry_run)
      end

      def run_rollback(runner, migration_id, dry_run:)
        puts "Rolling back migration: #{migration_id} (#{mode_label(dry_run)})"
        puts '=' * 70

        result = runner.rollback(migration_id, dry_run: dry_run)
        print_results([result])
        finish([result], dry_run: dry_run)
      end

      # A file path that defines one migration selects it regardless of the
      # basename. Otherwise: exact ID first, then a unique partial match on
      # the ID or class name. Several partial matches are refused rather
      # than picking one.
      def find_migration_class(migration_id, specific_file: nil)
        migrations = Familia::Migration.migrations
        return migrations.first if specific_file && migrations.size == 1

        exact = migrations.find { |m| m.migration_id == migration_id }
        return exact if exact

        term    = migration_id.downcase
        matches = migrations.select do |m|
          m.migration_id.to_s.downcase.include?(term) ||
            m.name.downcase.include?(term.tr('_', ''))
        end

        return matches.first if matches.size == 1

        if matches.empty?
          puts "Migration not found: #{migration_id}"
          puts
          puts 'Available migrations:'
          list_migration_ids(migrations)
        else
          puts "Ambiguous migration ID: #{migration_id}"
          puts
          puts 'Matches:'
          list_migration_ids(matches)
        end
        exit 1
      end

      def list_migration_ids(migrations)
        migrations.each { |m| puts "  - #{m.migration_id}" }
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

      def mode_label(dry_run)
        dry_run ? 'DRY RUN' : 'EXECUTE'
      end

      def print_results(results)
        results.each do |result|
          status_icon  = STATUS_ICONS.fetch(result[:status], '?')
          dry_run_note = result[:dry_run] ? ' (dry run)' : ''
          puts "#{status_icon} #{result[:migration_id]} #{result[:status]}#{dry_run_note}"

          puts "    Error: #{result[:error]}" if result[:error]

          next unless result[:stats]&.any?

          result[:stats].each do |key, value|
            puts "    #{key}: #{value}"
          end
        end
      end

      def finish(results, dry_run:)
        ok     = results.count { |r| MigrateRunner::OK_STATUSES.include?(r[:status]) || r[:status] == :rolled_back }
        not_ok = results.size - ok
        note   = dry_run ? ' (dry run, nothing recorded)' : ''

        puts
        puts '=' * 70
        puts "Completed: #{ok} ok, #{not_ok} not ok#{note}"

        exit 1 if not_ok > 0
      end
    end

    register 'migrate', MigrateCommand
  end
end
