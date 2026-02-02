# spec/cli/migrate_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Migrate Command', type: :cli do
  # Migration file that follows the Familia::Migration::Base pattern
  let(:migration_content) do
    <<~RUBY
      require 'familia/migration'

      module OTS
        module Migration
          class TestMigration#{SecureRandom.hex(4)} < Familia::Migration::Base
            self.migration_id = 'test_migration'
            self.description = 'Test migration for specs'
            self.dependencies = []

            def migration_needed?
              true
            end

            def migrate
              track_stat(:records_processed, 0)
            end
          end
        end
      end
    RUBY
  end

  let(:failing_migration_content) do
    <<~RUBY
      require 'familia/migration'

      module OTS
        module Migration
          class FailingMigration#{SecureRandom.hex(4)} < Familia::Migration::Base
            self.migration_id = 'failing_migration'
            self.description = 'Failing migration for specs'
            self.dependencies = []

            def migration_needed?
              true
            end

            def migrate
              raise "Migration failed intentionally"
            end
          end
        end
      end
    RUBY
  end

  before(:each) do
    # Clear migration registry to prevent pollution between tests
    Familia::Migration.migrations.clear if defined?(Familia::Migration)
  end

  describe 'without arguments' do
    it 'displays migration status' do
      output = run_cli_command_quietly('migrate', '--status')
      expect(output[:stdout]).to match(/Migration Status|No migrations registered/)
    end
  end

  describe 'with migration directory' do
    before do
      @migration_path = create_temp_migration('01_test_migration.rb', migration_content)
      @migration_dir = File.dirname(@migration_path)
    end

    it 'loads migrations from custom directory' do
      output = run_cli_command_quietly('migrate', '--dir', @migration_dir, '--status')
      expect(output[:stdout]).to include('Loaded 1 migrations from')
    end

    it 'runs migration in dry-run mode by default' do
      output = run_cli_command_quietly('migrate', 'test_migration', '--dir', @migration_dir)
      expect(output[:stdout]).to include('DRY RUN')
    end

    it 'runs migration with --run flag' do
      output = run_cli_command_quietly('migrate', 'test_migration', '--dir', @migration_dir, '--run')
      expect(output[:stdout]).to include('EXECUTE')
    end
  end

  describe 'with non-existent migration' do
    before do
      @migration_path = create_temp_migration('01_test_migration.rb', migration_content)
      @migration_dir = File.dirname(@migration_path)
    end

    it 'reports migration not found' do
      output = run_cli_command_quietly('migrate', 'nonexistent', '--dir', @migration_dir)
      expect(output[:stdout]).to include('Migration not found')
    end
  end

  describe 'with non-existent directory' do
    it 'reports directory not found' do
      output = run_cli_command_quietly('migrate', '--dir', '/nonexistent/path')
      expect(output[:stdout]).to include('Migration directory not found')
    end
  end

  describe 'argument variations' do
    before do
      @migration_path = create_temp_migration('01_test_migration.rb', migration_content)
      @migration_dir = File.dirname(@migration_path)
    end

    it 'accepts -r short flag' do
      output = run_cli_command_quietly('migrate', 'test_migration', '--dir', @migration_dir, '-r')
      expect(output[:stdout]).to include('EXECUTE')
    end

    it 'accepts -d short flag for directory' do
      output = run_cli_command_quietly('migrate', '-d', @migration_dir, '--status')
      expect(output[:stdout]).to include('Loaded 1 migrations from')
    end
  end

  describe 'validation' do
    before do
      @migration_path = create_temp_migration('01_test_migration.rb', migration_content)
      @migration_dir = File.dirname(@migration_path)
    end

    it 'validates migration dependencies' do
      output = run_cli_command_quietly('migrate', '--dir', @migration_dir, '--validate')
      expect(output[:stdout]).to include('Validating migration dependencies')
    end
  end
end
