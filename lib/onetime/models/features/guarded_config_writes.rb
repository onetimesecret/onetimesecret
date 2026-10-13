# lib/onetime/models/features/guarded_config_writes.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Create, update and delete for the per-domain config models (one record
      # per CustomDomain, keyed by domain_id), each atomic against a concurrent
      # writer of the same record.
      #
      # A request loads the record in raise_concerns and writes it in process.
      # Writing that copy back reverts any field another writer committed in
      # between (commit_fields and save write every field), and an audit event
      # computed from it describes a state the write never replaced. These
      # methods read the record after WATCH on its key and commit with
      # MULTI/EXEC, which Redis discards when the key changed after the WATCH;
      # the read and the write then run again (ATTEMPTS in all).
      #
      # WATCH, the read and MULTI/EXEC must share one connection, so they run
      # inside Onetime.with_pinned_dbclient. A partial boot has no pool; the
      # model's own client serves all three there.
      #
      # Enable with +feature :guarded_config_writes+. The model's identifier
      # must be its domain_id.
      module GuardedConfigWrites
        Familia::Base.add_feature self, :guarded_config_writes

        ATTEMPTS = 3

        # A create lost to a concurrent create of the same domain's record.
        # Subclasses Onetime::Problem, which create! raised for an existing
        # record before this class existed.
        class ConfigExistsError < Onetime::Problem; end

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module InstanceMethods
          # Writes +values+ to the stored record, re-read under WATCH, and
          # leaves its other fields as stored. This copy takes the same values.
          #
          # @return [self]
          # @raise [Familia::KeyNotFoundError] no stored record
          def update_stored!(**values)
            self.class.update_for_domain!(identifier) do |stored|
              values.each { |name, value| stored.public_send(:"#{name}=", value) }
            end
            adopt_stored_values!(values)
          end

          private

          # Takes +values+ on this copy without marking them unsaved.
          #
          # @param values [Hash{Symbol => Object}]
          # @return [self]
          def adopt_stored_values!(values)
            values.each { |name, value| public_send(:"#{name}=", value) }
            clear_dirty!(*values.keys)
            self
          end
        end

        module ClassMethods
          # Read-modify-write of the stored record.
          #
          # @param domain_id [String]
          # @yield [config] the stored record, read under WATCH. The block
          #   reads it and assigns to it; it must not write, because it runs
          #   again on each retry. Raising aborts without writing.
          # @return [Array(Familia::Horreum, Object)] the committed record and
          #   the block's value from the attempt that committed
          # @raise [Familia::KeyNotFoundError] no record for domain_id
          # @raise [Familia::OptimisticLockError] still changing after ATTEMPTS
          def update_for_domain!(domain_id)
            guarded_attempts(domain_id) do |config|
              raise Familia::KeyNotFoundError, dbkey(domain_id) unless config

              value = yield config
              [config.commit_fields, [config, value]]
            end
          end

          # update_for_domain! that writes only while +condition+ holds for
          # the stored record, for a writer whose input was computed from a
          # state the record may since have left (a background job).
          #
          # @param condition [Proc] called with the stored record
          # @yield [config] as for update_for_domain!
          # @return [Array(Familia::Horreum, Object), nil] as update_for_domain!,
          #   or nil (nothing written) when the record is gone or the
          #   condition is false
          # @raise [Familia::OptimisticLockError] still changing after ATTEMPTS
          def update_for_domain_if(domain_id, condition)
            guarded_attempts(domain_id) do |config|
              next [nil, nil] unless config && condition.call(config)

              value = yield config
              [config.commit_fields, [config, value]]
            end
          end

          # Deletes the stored record and returns it as it was when deleted,
          # so an audit event can describe what was removed. Of concurrent
          # deletes, exactly one gets the record.
          #
          # @param domain_id [String]
          # @return [Familia::Horreum, nil] the deleted record, nil when there
          #   was none
          # @raise [Familia::OptimisticLockError] still changing after ATTEMPTS
          def remove_for_domain!(domain_id)
            return nil if domain_id.to_s.empty?

            guarded_attempts(domain_id) do |config|
              next [nil, nil] unless config

              [config.destroy!, config]
            end
          end

          # @param domain_id [String]
          # @return [Boolean] whether this call deleted a record
          def delete_for_domain!(domain_id)
            !remove_for_domain!(domain_id).nil?
          end

          # Updates the stored record, or saves the one +build+ returns when
          # there is none. A create lost to a concurrent create becomes an
          # update of the record that won.
          #
          # @param domain_id [String]
          # @param message [String] the ConfigExistsError message
          # @param build [Proc] returns the unsaved record
          # @yield [config] as for update_for_domain!
          # @return [Familia::Horreum] the saved record
          # @raise as update_for_domain!
          def upsert_for_domain!(domain_id, message, build:, &)
            unless exists_for_domain?(domain_id)
              begin
                return save_new_config!(build.call, message)
              rescue ConfigExistsError
                # Created concurrently: update it below.
              end
            end

            update_for_domain!(domain_id, &).first
          end

          # create!'s early check, before it validates attributes.
          # save_new_config! repeats it atomically.
          #
          # @raise [ConfigExistsError]
          def refuse_existing_config!(domain_id, message)
            raise ConfigExistsError, message if exists_for_domain?(domain_id)
          end

          # Saves a new record unless one exists for its domain_id, in one
          # WATCH-guarded step (Familia's save_if_not_exists!).
          #
          # @param config [Familia::Horreum] the unsaved record
          # @param message [String] the ConfigExistsError message
          # @return [Familia::Horreum] config
          # @raise [ConfigExistsError] a record exists for the domain_id
          def save_new_config!(config, message)
            with_guarded_connection { config.save_if_not_exists! }
            config
          rescue Familia::RecordExistsError
            raise ConfigExistsError, message
          end

          private

          # @yield [config] the stored record or nil, read after WATCH
          # @yieldreturn [Array(Object, Object)] the MULTI/EXEC result (nil
          #   when the block wrote nothing) and the value to return
          def guarded_attempts(domain_id)
            key = dbkey(domain_id)
            with_guarded_connection do |conn|
              ATTEMPTS.times do
                conn.watch(key)
                begin
                  result, value = yield load(domain_id)
                ensure
                  # No-op after EXEC; otherwise clears a WATCH that would
                  # follow the connection back into the pool.
                  conn.unwatch
                end
                if result.is_a?(Familia::MultiResult)
                  next if result.aborted?
                  raise Onetime::Problem, "#{name} write for #{domain_id} failed" unless result.successful?
                end

                return value
              end
              raise Familia::OptimisticLockError, "#{key} changed during #{ATTEMPTS} attempts"
            end
          end

          def with_guarded_connection
            return yield(dbclient) unless Onetime::Runtime.infrastructure.database_pool

            Onetime.with_pinned_dbclient { yield dbclient }
          end
        end
      end
    end
  end
end
