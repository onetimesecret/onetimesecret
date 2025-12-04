# spec/cli/migrate_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Migrate Command', type: :cli do
  let(:migration_content) do
    <<~RUBY
      module Onetime
        class Migration
          def self.run(run: false)
            true
          end
        end
      end
    RUBY
  end

  describe 'without arguments' do
    it 'displays usage and available migrations' do
      output = run_cli_command_quietly('migrate')
      expect(output[:stdout]).to include('Usage: ots migrate MIGRATION_SCRIPT')
      expect(output[:stdout]).to include('Available migrations')
    end
  end

  describe 'with migration file' do
    before do
      @migration_path = create_temp_migration('test_migration.rb', migration_content)
    end

    it 'runs migration in dry-run mode by default' do
      output = run_cli_command_quietly('migrate', @migration_path)
      expect(output[:stdout]).to include('Dry run completed successfully')
    end

    it 'runs migration with --run flag' do
      output = run_cli_command_quietly('migrate', @migration_path, '--run')
      expect(output[:stdout]).to include('Migration completed successfully')
    end

    it 'handles migration failure' do
      # Create a migration that fails
      failing_migration = <<~RUBY
        module Onetime
          class Migration
            def self.run(run: false)
              false
            end
          end
        end
      RUBY
      failing_path = create_temp_migration('failing_migration.rb', failing_migration)

      expect {
        run_cli_command('migrate', failing_path)
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end

  describe 'with non-existent migration' do
    it 'reports migration not found' do
      output = run_cli_command_quietly('migrate', 'nonexistent.rb')
      expect(output[:stdout]).to include('Migration script not found')
    end
  end

  describe 'argument variations' do
    before do
      @migration_path = create_temp_migration('test_migration.rb', migration_content)
    end

    it 'accepts -r short flag' do
      output = run_cli_command_quietly('migrate', @migration_path, '-r')
      expect(output[:stdout]).to include('Migration completed successfully')
    end
  end
end
