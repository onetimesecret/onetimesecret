# lib/onetime/cli/migrate_runner.rb
#
# frozen_string_literal: true

require 'familia/migration'

module Onetime
  module CLI
    # Execution policy for `bin/ots migrate` on top of Familia's Runner.
    #
    # Familia::Migration::Runner supplies discovery, dependency ordering,
    # registry access, and the preconditions for a rollback. This subclass
    # owns the outcome policy so that batch execution, single-migration
    # execution, and rollback all follow one invariant:
    #
    #   A modifying state transition is serialized per migration, checked
    #   under that lock, runs the full lifecycle (prepare,
    #   migration_needed?, migrate / prepare, down), and updates the registry
    #   before releasing the lock.
    #
    # Compared with the parent class:
    #
    # - Every entry point defaults to dry_run: true. The CLI passes the
    #   operator's choice explicitly; nothing modifies data by default.
    # - A migration whose #migrate returns false is :failed, not :success.
    #   Migrations use the false return to refuse an unsafe apply. #down has
    #   no return convention; only raising or record errors fail a rollback.
    # - Isolated record errors (tracked via `track_stat(:errors)` or a Model
    #   or Pipeline `error_count`) make the outcome :partial. A partial run
    #   is not recorded, so it can be re-run once the errors are addressed.
    # - A clean `migration_needed? == false` means the migration's target
    #   state is already satisfied. It remains a :skipped result; modifying
    #   runs record it, while dry-run batches treat it as a satisfied
    #   dependency without recording anything.
    # - A batch stops at the first outcome that is not :success or :skipped.
    #   Both outcomes satisfy later dependencies in that batch.
    # - A migration that is already recorded as applied is refused for a
    #   modifying single run (:already_applied); a dry run still previews it.
    # - Modifying apply and rollback paths share a token-checked,
    #   per-migration Redis lock. Dry runs never acquire it. Applied-state and
    #   dependency preconditions are checked under the lock.
    # - Rollback instantiates the migration with the run mode, calls #prepare
    #   before #down, and removes applied state only after #down succeeds
    #   on an actual run.
    #
    # Result hashes carry :migration_id, :dry_run, :status, :stats and,
    # when relevant, :error, :errors (record error count), :applied_at and
    # :duration_ms.
    class MigrateRunner < Familia::Migration::Runner
      OK_STATUSES = [:success, :skipped].freeze

      # Run all pending migrations in dependency order, stopping at the
      # first outcome that is not :success or :skipped.
      #
      # @param dry_run [Boolean] preview only (default)
      # @param limit [Integer, nil] maximum number of migrations to run
      # @return [Array<Hash>] one result per migration attempted
      def run(dry_run: true, limit: nil)
        pending_migrations = topological_sort(pending)
        pending_migrations = pending_migrations.first(limit) if limit

        results   = []
        satisfied = Set.new
        pending_migrations.each do |klass|
          result = begin
            run_one(klass, dry_run: dry_run, satisfied: satisfied)
          rescue Familia::Migration::Errors::DependencyNotMet => ex
            { migration_id: klass.migration_id, dry_run: dry_run, stats: {}, status: :failed, error: ex.message }
          end
          results << result
          satisfied << klass.migration_id if OK_STATUSES.include?(result[:status])
          break unless OK_STATUSES.include?(result[:status])
        end
        results
      end

      # Run one migration through the full forward lifecycle.
      #
      # @param migration_class_or_id [Class, String] migration class or exact ID
      # @param dry_run [Boolean] preview only (default)
      # @param satisfied [Enumerable<String>] IDs to treat as applied in
      #   addition to the registry (a batch dry run records nothing, so it
      #   passes the IDs it has already previewed successfully)
      # @return [Hash] result with :status in
      #   :success, :skipped, :partial, :failed, :already_applied
      # @raise [Familia::Migration::Errors::DependencyNotMet] when a declared
      #   dependency is neither recorded as applied nor in `satisfied`
      def run_one(migration_class_or_id, dry_run: true, satisfied: [])
        klass = resolve_migration(migration_class_or_id)
        id    = klass.migration_id

        return execute_forward(klass, dry_run: true, satisfied: satisfied) if dry_run

        with_modification_lock(id) do
          execute_forward(klass, dry_run: false, satisfied: satisfied)
        end
      end

      # Roll back an applied, reversible migration with no applied dependents.
      #
      # @param migration_id [String] exact migration ID
      # @param dry_run [Boolean] preview only (default)
      # @return [Hash] result with :status in :rolled_back, :partial, :failed
      # @raise [Familia::Migration::Errors::NotFound]
      # @raise [Familia::Migration::Errors::NotApplied]
      # @raise [Familia::Migration::Errors::HasDependents]
      # @raise [Familia::Migration::Errors::NotReversible]
      def rollback(migration_id, dry_run: true)
        klass = resolve_migration(migration_id)

        return execute_rollback(klass, migration_id, dry_run: true) if dry_run

        with_modification_lock(migration_id) do
          execute_rollback(klass, migration_id, dry_run: false)
        end
      end

      private

      def execute_forward(klass, dry_run:, satisfied:)
        id = klass.migration_id

        (klass.dependencies || []).each do |dep_id|
          next if satisfied.include?(dep_id) || @registry.applied?(dep_id)

          raise Familia::Migration::Errors::DependencyNotMet,
            "Dependency #{dep_id} not applied for #{id}"
        end

        result = { migration_id: id, dry_run: dry_run, stats: {} }

        applied_at = @registry.applied_at(id)
        if applied_at
          result[:applied_at] = applied_at
          unless dry_run
            result[:status] = :already_applied
            result[:error]  = "already applied at #{applied_at.utc.iso8601}; not re-run"
            return result
          end
        end

        instance = klass.new(run: !dry_run)
        started  = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          instance.prepare

          unless instance.migration_needed?
            finish_modifying_result(result, instance, nil, started, success: :skipped)
            if result[:status] == :skipped && !dry_run
              @registry.record_applied(instance, registry_stats(instance, result))
            end
            return result
          end

          returned = instance.migrate
          finish_modifying_result(result, instance, returned, started)

          if result[:status] == :success && !dry_run
            @registry.record_applied(instance, registry_stats(instance, result))
          end
        rescue StandardError => ex
          result[:status] = :failed
          result[:error]  = ex.message
          result[:stats]  = instance.stats
          @logger.error { "Migration #{id} failed: #{ex.message}" }
        end

        result
      end

      def execute_rollback(klass, migration_id, dry_run:)
        unless @registry.applied?(migration_id)
          raise Familia::Migration::Errors::NotApplied,
            "Migration #{migration_id} is not applied"
        end

        applied_ids = @registry.all_applied.to_set { |entry| entry[:migration_id] }
        @migrations.each do |migration|
          next unless (migration.dependencies || []).include?(migration_id)
          next unless applied_ids.include?(migration.migration_id)

          raise Familia::Migration::Errors::HasDependents,
            "Cannot rollback: #{migration.migration_id} depends on #{migration_id}"
        end

        instance = klass.new(run: !dry_run)

        unless instance.reversible?
          raise Familia::Migration::Errors::NotReversible,
            "Migration #{migration_id} does not have a down method"
        end

        result  = { migration_id: migration_id, dry_run: dry_run, stats: {} }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          instance.prepare
          instance.down
          finish_modifying_result(result, instance, nil, started, success: :rolled_back)

          @registry.record_rollback(migration_id) if result[:status] == :rolled_back && !dry_run
        rescue StandardError => ex
          result[:status] = :failed
          result[:error]  = ex.message
          result[:stats]  = instance.stats
          @logger.error { "Rollback #{migration_id} failed: #{ex.message}" }
        end

        result
      end

      # Migrations have no bounded runtime, so an expiring lease could admit a
      # second writer while the first still owns the operation. A token-checked,
      # non-expiring lock fails closed instead: normal exits release it in
      # `ensure`; a killed process leaves a key for operator inspection before
      # any retry of an indeterminate migration state.
      def with_modification_lock(migration_id)
        lock_key = "#{@registry.prefix}:lock:#{migration_id}"

        begin
          lock  = Familia::Lock.new(lock_key, dbclient: @registry.client, no_expiration: true)
          token = lock.acquire(ttl: nil)
        rescue StandardError => ex
          return lock_failure_result(
            migration_id,
            "could not acquire migration lock #{lock_key}: #{ex.message}",
          )
        end

        unless token
          return lock_failure_result(
            migration_id,
            "migration lock #{lock_key} is held by another modifying process; no changes made by this process",
          )
        end

        result = nil
        begin
          result = yield
        ensure
          release_modification_lock(lock, token, lock_key, migration_id, result)
        end
        result
      end

      def release_modification_lock(lock, token, lock_key, migration_id, result)
        released = lock.release(token)
        return if released

        mark_lock_release_failure(
          result,
          migration_id,
          "migration lock #{lock_key} was not released; inspect it before retrying",
        )
      rescue StandardError => ex
        mark_lock_release_failure(
          result,
          migration_id,
          "could not release migration lock #{lock_key}: #{ex.message}; inspect it before retrying",
        )
      end

      def mark_lock_release_failure(result, migration_id, message)
        @logger.error { "Migration #{migration_id} lock failure: #{message}" }
        return unless result

        result[:status] = :failed
        result[:error]  = [result[:error], message].compact.join('; ')
      end

      def lock_failure_result(migration_id, error)
        @logger.error { "Migration #{migration_id} lock failure: #{error}" }
        { migration_id: migration_id, dry_run: false, stats: {}, status: :failed, error: error }
      end

      # Classify a completed lifecycle step that did not raise, including a
      # clean not-needed check. The false-return rule applies to #migrate only
      # (Base documents a Boolean return and cli_run exits 1 on false); #down
      # and the not-needed path have no return convention, so callers pass nil.
      def finish_modifying_result(result, instance, returned, started, success: :success)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        errors  = record_error_count(instance)

        result[:stats]       = instance.stats
        result[:duration_ms] = (elapsed * 1000).round

        if errors > 0
          result[:status] = :partial
          result[:errors] = errors
          result[:error]  = "#{errors} record error(s); not recorded, re-run after investigating"
        elsif returned == false
          result[:status] = :failed
          result[:error]  = 'migration reported failure (returned false)'
        else
          result[:status] = success
        end
      end

      # Isolated per-record errors. Model and Pipeline count them in both
      # `error_count` and the :errors stat; Base migrations that isolate
      # their own loop use `track_stat(:errors)`.
      def record_error_count(instance)
        from_stats = instance.stats[:errors].to_i
        return from_stats unless instance.respond_to?(:error_count)

        [from_stats, instance.error_count.to_i].max
      end

      def registry_stats(instance, result)
        extra                 = {
          duration_ms: result[:duration_ms],
          reversible: instance.reversible?,
          errors: 0,
        }
        extra[:keys_scanned]  = instance.total_scanned if instance.respond_to?(:total_scanned)
        extra[:keys_modified] = instance.records_updated if instance.respond_to?(:records_updated)
        instance.stats.merge(extra)
      end
    end
  end
end
