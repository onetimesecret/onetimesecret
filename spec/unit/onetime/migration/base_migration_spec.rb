# spec/unit/onetime/migration/base_migration_spec.rb
#
# frozen_string_literal: true

# Tests for Onetime::BaseMigration framework
#

require 'spec_helper'
require 'onetime/migration/base_migration'

RSpec.describe Onetime::BaseMigration do
  include_context "migration_test_context"

  # Test implementation that overrides abstract methods
  let(:test_migration_class) do
    Class.new(described_class) do
      attr_accessor :migration_needed_result, :migrate_called

      def initialize
        super
        @migration_needed_result = true
        @migrate_called = false
      end

      def migration_needed?
        @migration_needed_result
      end

      def migrate
        @migrate_called = true
        true
      end
    end
  end

  let(:migration) { test_migration_class.new }

  describe '#initialize' do
    it 'initializes with empty options hash' do
      expect(migration.options).to eq({})
    end

    it 'initializes stats as auto-incrementing hash' do
      expect(migration.stats).to be_a(Hash)
      expect(migration.stats[:nonexistent]).to eq(0)
    end

    it 'stats hash auto-increments on access' do
      migration.stats[:test] += 1
      expect(migration.stats[:test]).to eq(1)
    end
  end

  describe '#dry_run?' do
    it 'returns true when run option is false' do
      migration.options = { run: false }
      expect(migration.dry_run?).to be true
    end

    it 'returns true when run option is absent' do
      migration.options = {}
      expect(migration.dry_run?).to be true
    end

    it 'returns false when run option is true' do
      migration.options = { run: true }
      expect(migration.dry_run?).to be false
    end
  end

  describe '#actual_run?' do
    it 'returns false when run option is false' do
      migration.options = { run: false }
      expect(migration.actual_run?).to be false
    end

    it 'returns nil (falsey) when run option is absent' do
      migration.options = {}
      expect(migration.actual_run?).to be_nil
      expect(migration.actual_run?).to be_falsey
    end

    it 'returns true when run option is true' do
      migration.options = { run: true }
      expect(migration.actual_run?).to be true
    end
  end

  describe '#for_realsies_this_time?' do
    it 'executes block and returns true in actual run mode' do
      migration.options = { run: true }
      executed = false

      result = migration.for_realsies_this_time? do
        executed = true
      end

      expect(result).to be true
      expect(executed).to be true
    end

    it 'does not execute block and returns false in dry run mode' do
      migration.options = { run: false }
      executed = false

      result = migration.for_realsies_this_time? do
        executed = true
      end

      expect(result).to be false
      expect(executed).to be false
    end

    it 'does not execute block when run option is absent' do
      migration.options = {}
      executed = false

      result = migration.for_realsies_this_time? do
        executed = true
      end

      expect(result).to be false
      expect(executed).to be false
    end
  end

  describe '#track_stat' do
    it 'increments stat by 1 by default' do
      migration.track_stat(:processed)
      expect(migration.stats[:processed]).to eq(1)
    end

    it 'increments stat by custom amount' do
      migration.track_stat(:processed, 5)
      expect(migration.stats[:processed]).to eq(5)
    end

    it 'accumulates multiple increments' do
      migration.track_stat(:processed)
      migration.track_stat(:processed)
      migration.track_stat(:processed, 3)
      expect(migration.stats[:processed]).to eq(5)
    end

    it 'tracks different stats independently' do
      migration.track_stat(:processed, 10)
      migration.track_stat(:skipped, 3)
      migration.track_stat(:errors, 1)

      expect(migration.stats[:processed]).to eq(10)
      expect(migration.stats[:skipped]).to eq(3)
      expect(migration.stats[:errors]).to eq(1)
    end

    it 'returns nil' do
      result = migration.track_stat(:test)
      expect(result).to be_nil
    end
  end

  describe '.cli_run' do
    context 'with --check flag' do
      it 'returns 0 when migration not needed' do
        allow_any_instance_of(test_migration_class).to receive(:migration_needed?).and_return(false)
        expect(test_migration_class.cli_run(['--check'])).to eq(0)
      end

      it 'returns 1 when migration is needed' do
        allow_any_instance_of(test_migration_class).to receive(:migration_needed?).and_return(true)
        expect(test_migration_class.cli_run(['--check'])).to eq(1)
      end
    end

    context 'without --check flag' do
      it 'returns 0 for successful migration with --run flag' do
        allow_any_instance_of(test_migration_class).to receive(:migrate).and_return(true)
        expect(test_migration_class.cli_run(['--run'])).to eq(0)
      end

      it 'returns 0 for migration not needed' do
        allow_any_instance_of(test_migration_class).to receive(:migration_needed?).and_return(false)
        expect(test_migration_class.cli_run([])).to eq(0)
      end

      it 'returns 1 for failed migration' do
        allow_any_instance_of(test_migration_class).to receive(:migrate).and_return(false)
        expect(test_migration_class.cli_run(['--run'])).to eq(1)
      end

      it 'returns 0 for dry run (no --run flag)' do
        allow_any_instance_of(test_migration_class).to receive(:migrate).and_return(true)
        expect(test_migration_class.cli_run([])).to eq(0)
      end
    end
  end

  describe '.run' do
    it 'returns nil when migration not needed' do
      allow_any_instance_of(test_migration_class).to receive(:migration_needed?).and_return(false)
      result = test_migration_class.run(dry_run_options)
      expect(result).to be_nil
    end

    it 'calls migrate when migration is needed' do
      instance = test_migration_class.new
      allow(test_migration_class).to receive(:new).and_return(instance)
      instance.migration_needed_result = true

      test_migration_class.run(dry_run_options)
      expect(instance.migrate_called).to be true
    end

    it 'sets options on migration instance' do
      instance = test_migration_class.new
      allow(test_migration_class).to receive(:new).and_return(instance)

      test_migration_class.run(actual_run_options)
      expect(instance.options).to eq(actual_run_options)
    end

    it 'calls prepare before checking if migration is needed' do
      instance = test_migration_class.new
      prepare_called = false

      allow(test_migration_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:prepare) { prepare_called = true }
      allow(instance).to receive(:migration_needed?).and_wrap_original do |m|
        expect(prepare_called).to be true
        m.call
      end

      test_migration_class.run(dry_run_options)
    end
  end

  describe '#prepare' do
    it 'provides default implementation that does not raise' do
      expect { migration.prepare }.not_to raise_error
    end
  end

  describe 'abstract methods' do
    let(:base_migration) { described_class.new }

    it '#migration_needed? raises NotImplementedError' do
      expect { base_migration.migration_needed? }.to raise_error(NotImplementedError)
    end

    it '#migrate raises NotImplementedError' do
      expect { base_migration.migrate }.to raise_error(NotImplementedError)
    end
  end
end
