# spec/cli/migrate_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# Tests for migrate_command.rb and MigrateRunner.
#
# One invariant covers every modifying path (batch, single ID, rollback):
# a run is dependency-checked, runs the full lifecycle, and is recorded in
# the registry exactly once, only after it succeeds. Nothing is recorded
# without --run.
#
# The registry is backed by an in-memory stand-in for the sorted set and
# hash it keeps in Redis, so the specs assert on recorded state directly.
RSpec.describe 'Migrate Command', type: :cli do
  # In-memory stand-in for the two Redis structures Familia::Migration::Registry
  # uses: the applied sorted set and the metadata hash.
  class FakeMigrationStore
    # Keys a Model migration's SCAN will find (see #scan).
    attr_accessor :scan_keys

    def initialize
      @zsets     = Hash.new { |h, k| h[k] = {} }
      @hashes    = Hash.new { |h, k| h[k] = {} }
      @scan_keys = []
    end

    def ping
      'PONG'
    end

    # Single-page SCAN: every configured key on the first call.
    def scan(_cursor, match: nil, count: nil)
      ['0', scan_keys]
    end

    def zscore(key, member)
      @zsets[key][member]
    end

    def zadd(key, score, member)
      @zsets[key][member] = score.to_f
      true
    end

    def zrem(key, member)
      @zsets[key].delete(member) ? 1 : 0
    end

    def zrange(key, start, stop, withscores: false)
      entries = @zsets[key].sort_by { |member, score| [score, member] }
      entries = entries[start..stop] || []
      withscores ? entries : entries.map(&:first)
    end

    def hget(key, field)
      @hashes[key][field]
    end

    def hset(key, field, value)
      @hashes[key][field] = value
      1
    end

    def applied_ids
      @zsets['familia:migrations:applied'].keys.sort
    end

    def applied_score(migration_id)
      @zsets['familia:migrations:applied'][migration_id]
    end

    def metadata(migration_id)
      json = @hashes['familia:migrations:metadata'][migration_id]
      json && JSON.parse(json)
    end
  end

  let(:store) { FakeMigrationStore.new }
  let(:probe_path) { File.join(temp_migrations_dir, 'probe.txt') }

  def migration_source(klass, id, body, base: 'Familia::Migration::Base', deps: '[]')
    <<~RUBY
      require 'familia/migration'

      module OTS
        module Migration
          class #{klass}#{SecureRandom.hex(4)} < #{base}
            self.migration_id = '#{id}'
            self.description = 'Spec migration #{id}'
            self.dependencies = #{deps}

            def migration_needed?
              true
            end

      #{body}
          end
        end
      end
    RUBY
  end

  let(:success_migration) do
    migration_source('SuccessMigration', 'success_migration', <<~RUBY)
      def migrate
        track_stat(:records_processed, 0)
        true
      end
    RUBY
  end

  let(:failing_migration) do
    migration_source('FailingMigration', 'failing_migration', <<~RUBY)
      def migrate
        raise 'Migration failed intentionally'
      end
    RUBY
  end

  # Migrations return false to refuse an unsafe apply (see
  # migrations/2026-07-27/20260727_01_backfill_signin_config.rb).
  let(:refusing_migration) do
    migration_source('RefusingMigration', 'refusing_migration', <<~RUBY)
      def migrate
        false
      end
    RUBY
  end

  # A migration that isolates per-record errors the way Model migrations do.
  let(:partial_migration) do
    migration_source('PartialMigration', 'partial_migration', <<~RUBY)
      def migrate
        track_stat(:records_updated, 2)
        track_stat(:errors, 1)
        true
      end
    RUBY
  end

  let(:dependent_migration) do
    migration_source('DependentMigration', 'dependent_migration', <<~RUBY, deps: "['success_migration']")
      def migrate
        true
      end
    RUBY
  end

  # Reversible migration whose #down needs #prepare and guards its write
  # with the run mode, like a real migration would.
  let(:reversible_migration) do
    migration_source('ReversibleMigration', 'reversible_migration', <<~RUBY)
      def prepare
        @probe = '#{probe_path}'
      end

      def migrate
        for_realsies_this_time? { File.write(@probe, 'up') }
        true
      end

      def down
        raise 'prepare was not called before down' unless @probe

        for_realsies_this_time? { File.write(@probe, 'down') }
        true
      end
    RUBY
  end

  let(:exploding_rollback_migration) do
    migration_source('ExplodingRollback', 'exploding_rollback', <<~RUBY)
      def migrate
        true
      end

      def down
        raise 'down failed intentionally'
      end
    RUBY
  end

  # #down isolates a record error the way Model migrations do.
  let(:partial_rollback_migration) do
    migration_source('PartialRollback', 'partial_rollback', <<~RUBY)
      def migrate
        true
      end

      def down
        track_stat(:errors, 1)
        true
      end
    RUBY
  end

  # Base#migrate documents a Boolean return, but a migration whose last
  # expression is a stat or a log call returns nil.
  let(:nil_returning_migration) do
    migration_source('NilReturning', 'nil_returning', <<~RUBY)
      def migrate
        track_stat(:settings_updated)
      end
    RUBY
  end

  let(:skipping_migration) do
    migration_source('SkippingMigration', 'skipping_migration', <<~RUBY)
      def migration_needed?
        false
      end

      def migrate
        raise 'migrate must not run when migration_needed? is false'
      end
    RUBY
  end

  let(:prepare_raising_migration) do
    migration_source('PrepareRaising', 'prepare_raising', <<~RUBY)
      def prepare
        raise 'prepare exploded'
      end

      def migrate
        true
      end
    RUBY
  end

  let(:depends_on_partial_migration) do
    migration_source('DependsOnPartial', 'depends_on_partial', <<~RUBY, deps: "['partial_migration']")
      def migrate
        true
      end
    RUBY
  end

  # Familia::Migration::Model subclass driving the real SCAN and
  # per-record rescue path. The model only needs to satisfy
  # Model#familia_horreum_class? (`< Familia::Base`) and answer #prefix;
  # #load_from_key hands the key itself to #process_record.
  def model_migration_source(id, raise_on: nil)
    raise_line = raise_on ? "raise \"record \#{key} is malformed\" if key.end_with?('#{raise_on}')" : ''
    migration_source('ProbeModelMigration', id, <<~RUBY, base: 'Familia::Migration::Model')
      class ProbeModel
        include Familia::Base

        def self.prefix
          'probe'
        end
      end

      def prepare
        @model_class = self.class::ProbeModel
        @batch_size  = 10
        @dbclient    = Familia.dbclient
      end

      def load_from_key(key)
        key
      end

      def process_record(_obj, key)
        #{raise_line}
        track_stat(:records_updated)
      end
    RUBY
  end

  before(:each) do
    # Clear migration registry to prevent pollution between tests
    Familia::Migration.migrations.clear
    allow(Familia).to receive(:dbclient).and_return(store)
  end

  def write_migration(name, content)
    create_temp_migration(name, content)
    temp_migrations_dir
  end

  def migrate(*args)
    run_cli_command_quietly('migrate', *args)
  end

  describe 'without arguments' do
    it 'displays migration status' do
      output = migrate('--status')
      expect(output[:stdout]).to match(/Migration Status|No migrations registered/)
    end

    it 'shows status, not a run, when a directory has pending migrations' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir)
      expect(output[:stdout]).to include('Pending    success_migration')
      expect(output[:stdout]).to include('Preview with --dry-run; apply with --run')
      expect(store.applied_ids).to eq([])
    end

    it 'shows status without running when --status is combined with --run' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir, '--status', '--run')
      expect(output[:stdout]).to include('Migration Status')
      expect(output[:stdout]).to include('Pending    success_migration')
      expect(output[:stdout]).not_to include('Running')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'shows status without rolling back when --status is combined with --rollback --run' do
      dir = write_migration('01_reversible.rb', reversible_migration)
      migrate('reversible_migration', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'reversible_migration', '--status', '--run')
      expect(output[:stdout]).to include('Applied    reversible_migration')
      expect(output[:stdout]).not_to include('Rolling back')
      expect(File.read(probe_path)).to eq('up')
      expect(store.applied_ids).to eq(['reversible_migration'])
    end
  end

  describe 'option conflicts' do
    it 'refuses --run together with --dry-run' do
      output = migrate('--run', '--dry-run')
      expect(output[:stdout]).to include('Choose one of --run or --dry-run')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'loading' do
    it 'loads migrations from a custom directory' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir, '--status')
      expect(output[:stdout]).to include('Loaded 1 migrations from')
    end

    it 'accepts -d as the directory flag' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('-d', dir, '--status')
      expect(output[:stdout]).to include('Loaded 1 migrations from')
    end

    it 'reports a missing directory' do
      output = migrate('--dir', '/nonexistent/path')
      expect(output[:stdout]).to include('Migration directory not found')
      expect(last_exit_code).to eq(1)
    end

    it 'loads only the named file when given a path' do
      write_migration('01_success.rb', success_migration)
      path   = create_temp_migration('02_failing.rb', failing_migration)
      output = migrate(path)
      expect(output[:stdout]).to include("Loaded migration from #{path}")
      expect(output[:stdout]).to include('Running migration: failing_migration (DRY RUN)')
    end
  end

  describe 'batch execution' do
    it 'previews all pending migrations with --dry-run and records nothing' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir, '--dry-run')
      expect(output[:stdout]).to include('Running all pending migrations (DRY RUN)')
      expect(output[:stdout]).to include('✓ success_migration success (dry run)')
      expect(output[:stdout]).to include('nothing recorded')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'applies and records with --run, then has nothing pending' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('Running all pending migrations (EXECUTE)')
      expect(output[:stdout]).to include('✓ success_migration success')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['success_migration'])
      expect(store.metadata('success_migration')).to include('status' => 'applied', 'errors' => 0)

      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('No pending migrations to run')
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'stops at the first failure and records nothing for it' do
      write_migration('01_failing.rb', failing_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('✗ failing_migration failed')
      expect(output[:stdout]).to include('Error: Migration failed intentionally')
      expect(output[:stdout]).not_to include('success_migration success')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'stops at a partial result and leaves it unrecorded' do
      write_migration('01_partial.rb', partial_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('! partial_migration partial')
      expect(output[:stdout]).to include('1 record error(s)')
      expect(output[:stdout]).not_to include('success_migration success')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'orders a dependent after its dependency and records both' do
      write_migration('01_dependent.rb', dependent_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout].index('success_migration success')).to be < output[:stdout].index('dependent_migration success')
      expect(store.applied_ids).to eq(%w[dependent_migration success_migration])
    end

    # A dry run records nothing, so the dependent's registry check cannot
    # see the dependency it just previewed. The preview must still cover
    # every pending migration; migrations/2025-07-27 has exactly this shape
    # (20250727_03 depends on 20250727_02).
    it 'previews a dependency chain with --dry-run without aborting' do
      write_migration('01_dependent.rb', dependent_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--dry-run')
      expect(output[:stdout]).to include('✓ success_migration success (dry run)')
      expect(output[:stdout]).to include('✓ dependent_migration success (dry run)')
      expect(output[:stdout]).not_to include('DependencyNotMet')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'reports a dependency that is neither loaded nor applied as a failed row' do
      write_migration('01_success.rb', success_migration)
      dir    = write_migration('02_dependent_on_missing.rb', migration_source('MissingDep', 'missing_dep', <<~RUBY, deps: "['not_loaded']"))
        def migrate
          true
        end
      RUBY
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('✓ success_migration success')
      expect(output[:stdout]).to include('✗ missing_dep failed')
      expect(output[:stdout]).to include('Error: Dependency not_loaded not applied for missing_dep')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'does not run a migration whose dependency ended partial' do
      write_migration('01_depends_on_partial.rb', depends_on_partial_migration)
      dir    = write_migration('02_partial.rb', partial_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('! partial_migration partial')
      expect(output[:stdout]).not_to include('depends_on_partial')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'continues past a skipped migration and records only the applied one' do
      write_migration('01_skipping.rb', skipping_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--run')
      expect(output[:stdout]).to include('○ skipping_migration skipped')
      expect(output[:stdout]).to include('✓ success_migration success')
      expect(output[:stdout]).to include('Completed: 2 ok, 0 not ok')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'reports a failing outcome on --dry-run but records nothing' do
      write_migration('01_refusing.rb', refusing_migration)
      dir    = write_migration('02_success.rb', success_migration)
      output = migrate('--dir', dir, '--dry-run')
      expect(output[:stdout]).to include('✗ refusing_migration failed (dry run)')
      expect(output[:stdout]).to include('Completed: 0 ok, 1 not ok (dry run, nothing recorded)')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end
  end

  describe 'single migration execution' do
    it 'previews by default and records nothing' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('success_migration', '--dir', dir)
      expect(output[:stdout]).to include('Running migration: success_migration (DRY RUN)')
      expect(output[:stdout]).to include('✓ success_migration success (dry run)')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'applies and records exactly once with --run' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('success_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('Running migration: success_migration (EXECUTE)')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['success_migration'])
      first_score = store.applied_score('success_migration')

      output = migrate('success_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✗ success_migration already_applied')
      expect(last_exit_code).to eq(1)
      expect(store.applied_score('success_migration')).to eq(first_score)
    end

    it 'still previews an applied migration on a dry run' do
      dir = write_migration('01_success.rb', success_migration)
      migrate('success_migration', '--dir', dir, '--run')
      output = migrate('success_migration', '--dir', dir)
      expect(output[:stdout]).to include('✓ success_migration success (dry run)')
      expect(last_exit_code).to eq(0)
    end

    it 'accepts -r as the run flag' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('success_migration', '--dir', dir, '-r')
      expect(output[:stdout]).to include('EXECUTE')
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'refuses to run before a dependency is applied' do
      write_migration('01_success.rb', success_migration)
      dir    = write_migration('02_dependent.rb', dependent_migration)
      output = migrate('dependent_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('DependencyNotMet: Dependency success_migration not applied for dependent_migration')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'treats a raised error as failed and records nothing' do
      dir    = write_migration('01_failing.rb', failing_migration)
      output = migrate('failing_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✗ failing_migration failed')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'treats a false return as failed and records nothing' do
      dir    = write_migration('01_refusing.rb', refusing_migration)
      output = migrate('refusing_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✗ refusing_migration failed')
      expect(output[:stdout]).to include('returned false')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'treats isolated record errors as partial and records nothing' do
      dir    = write_migration('01_partial.rb', partial_migration)
      output = migrate('partial_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('! partial_migration partial')
      expect(output[:stdout]).to include('errors: 1')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'reports an unknown migration' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('nonexistent', '--dir', dir)
      expect(output[:stdout]).to include('Migration not found: nonexistent')
      expect(last_exit_code).to eq(1)
    end

    it 'previews with an explicit --dry-run and records nothing' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('success_migration', '--dir', dir, '--dry-run')
      expect(output[:stdout]).to include('Running migration: success_migration (DRY RUN)')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'treats a nil return as success and records it' do
      dir    = write_migration('01_nil.rb', nil_returning_migration)
      output = migrate('nil_returning', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✓ nil_returning success')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['nil_returning'])
    end

    it 'skips a migration that is not needed, exits 0, and records nothing' do
      dir    = write_migration('01_skipping.rb', skipping_migration)
      output = migrate('skipping_migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('○ skipping_migration skipped')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq([])
    end

    it 'treats a raising prepare as failed and records nothing' do
      dir    = write_migration('01_prepare_raising.rb', prepare_raising_migration)
      output = migrate('prepare_raising', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✗ prepare_raising failed')
      expect(output[:stdout]).to include('Error: prepare exploded')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'runs and records a migration selected by file path regardless of basename' do
      path   = create_temp_migration('nothing_in_common.rb', success_migration)
      output = migrate(path, '--run')
      expect(output[:stdout]).to include('Running migration: success_migration (EXECUTE)')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'resolves a unique partial match' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('success', '--dir', dir)
      expect(output[:stdout]).to include('Running migration: success_migration (DRY RUN)')
    end

    it 'refuses an ambiguous partial match' do
      write_migration('01_success.rb', success_migration)
      dir    = write_migration('02_failing.rb', failing_migration)
      output = migrate('migration', '--dir', dir, '--run')
      expect(output[:stdout]).to include('Ambiguous migration ID: migration')
      expect(output[:stdout]).to include('- success_migration')
      expect(output[:stdout]).to include('- failing_migration')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end
  end

  describe 'rollback' do
    it 'refuses a migration that is not applied' do
      dir    = write_migration('01_reversible.rb', reversible_migration)
      output = migrate('--dir', dir, '--rollback', 'reversible_migration', '--run')
      expect(output[:stdout]).to include('NotApplied: Migration reversible_migration is not applied')
      expect(last_exit_code).to eq(1)
    end

    it 'previews without --run and keeps applied state' do
      dir = write_migration('01_reversible.rb', reversible_migration)
      migrate('reversible_migration', '--dir', dir, '--run')
      expect(File.read(probe_path)).to eq('up')

      output = migrate('--dir', dir, '--rollback', 'reversible_migration')
      expect(output[:stdout]).to include('Rolling back migration: reversible_migration (DRY RUN)')
      expect(output[:stdout]).to include('✓ reversible_migration rolled_back (dry run)')
      expect(last_exit_code).to eq(0)
      expect(File.read(probe_path)).to eq('up')
      expect(store.applied_ids).to eq(['reversible_migration'])
    end

    it 'runs prepare then down with --run and removes applied state' do
      dir = write_migration('01_reversible.rb', reversible_migration)
      migrate('reversible_migration', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'reversible_migration', '--run')
      expect(output[:stdout]).to include('Rolling back migration: reversible_migration (EXECUTE)')
      expect(output[:stdout]).to include('✓ reversible_migration rolled_back')
      expect(last_exit_code).to eq(0)
      expect(File.read(probe_path)).to eq('down')
      expect(store.applied_ids).to eq([])
      expect(store.metadata('reversible_migration')).to include('status' => 'rolled_back')
    end

    it 'refuses a migration without down and keeps applied state' do
      dir = write_migration('01_success.rb', success_migration)
      migrate('success_migration', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'success_migration', '--run')
      expect(output[:stdout]).to include('NotReversible')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq(['success_migration'])
    end

    it 'keeps applied state when down raises' do
      dir = write_migration('01_exploding.rb', exploding_rollback_migration)
      migrate('exploding_rollback', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'exploding_rollback', '--run')
      expect(output[:stdout]).to include('✗ exploding_rollback failed')
      expect(output[:stdout]).to include('down failed intentionally')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq(['exploding_rollback'])
    end

    it 'refuses while an applied migration depends on it' do
      write_migration('01_dependent.rb', dependent_migration)
      dir = write_migration('02_success.rb', success_migration)
      migrate('--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'success_migration', '--run')
      expect(output[:stdout]).to include('HasDependents')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq(%w[dependent_migration success_migration])
    end

    it 'reports an unknown migration ID as NotFound' do
      dir    = write_migration('01_reversible.rb', reversible_migration)
      output = migrate('--dir', dir, '--rollback', 'nonexistent', '--run')
      expect(output[:stdout]).to include('NotFound: Migration nonexistent not found')
      expect(last_exit_code).to eq(1)
    end

    it 'accepts an explicit --dry-run and keeps applied state' do
      dir = write_migration('01_reversible.rb', reversible_migration)
      migrate('reversible_migration', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'reversible_migration', '--dry-run')
      expect(output[:stdout]).to include('Rolling back migration: reversible_migration (DRY RUN)')
      expect(last_exit_code).to eq(0)
      expect(File.read(probe_path)).to eq('up')
      expect(store.applied_ids).to eq(['reversible_migration'])
    end

    it 'keeps applied state when down counts record errors' do
      dir = write_migration('01_partial_rollback.rb', partial_rollback_migration)
      migrate('partial_rollback', '--dir', dir, '--run')

      output = migrate('--dir', dir, '--rollback', 'partial_rollback', '--run')
      expect(output[:stdout]).to include('! partial_rollback partial')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq(['partial_rollback'])
    end
  end

  describe 'Model migrations' do
    before do
      store.scan_keys = %w[probe:1:object probe:2:object probe:3:object]
    end

    it 'counts a per-record error once and ends partial, unrecorded' do
      dir    = write_migration('01_model.rb', model_migration_source('model_partial', raise_on: ':2:object'))
      output = migrate('model_partial', '--dir', dir, '--run')
      expect(output[:stdout]).to include('! model_partial partial')
      expect(output[:stdout]).to include('Error: 1 record error(s)')
      expect(output[:stdout]).to include('records_updated: 2')
      expect(output[:stdout]).to include('errors: 1')
      expect(last_exit_code).to eq(1)
      expect(store.applied_ids).to eq([])
    end

    it 'records scan and update counts for a clean run' do
      dir    = write_migration('01_model.rb', model_migration_source('model_clean'))
      output = migrate('model_clean', '--dir', dir, '--run')
      expect(output[:stdout]).to include('✓ model_clean success')
      expect(last_exit_code).to eq(0)
      expect(store.applied_ids).to eq(['model_clean'])
      expect(store.metadata('model_clean')).to include(
        'status' => 'applied', 'keys_scanned' => 3, 'keys_modified' => 3, 'errors' => 0
      )
    end
  end

  describe 'validation' do
    it 'validates migration dependencies' do
      dir    = write_migration('01_success.rb', success_migration)
      output = migrate('--dir', dir, '--validate')
      expect(output[:stdout]).to include('Validating migration dependencies')
      expect(output[:stdout]).to include('✓ All migrations valid')
    end

    it 'reports a missing dependency' do
      dir    = write_migration('01_dependent.rb', dependent_migration)
      output = migrate('--dir', dir, '--validate')
      expect(output[:stdout]).to include('missing_dependency: success_migration')
      expect(last_exit_code).to eq(1)
    end
  end
end
