# lib/onetime/models/features/with_migration_fields.rb
#
# frozen_string_literal: true

# Migration Support Feature
#
# Adds fields and methods to support v1 → v2 data migration.
# This feature should be removed after migration is complete.
#
# REMOVAL CHECKLIST:
# 1. Remove `feature :with_migration_fields` from all model files
# 2. Delete this file
# 3. Delete model-specific migration features:
#    - lib/onetime/models/customer/features/migration_fields.rb
#    - lib/onetime/models/organization/features/migration_fields.rb
#    - lib/onetime/models/custom_domain/features/migration_fields.rb
#    - lib/onetime/models/receipt/features/migration_fields.rb
#    - lib/onetime/models/secret/features/migration_fields.rb
# 4. Run migration validation to ensure all data is migrated
# 5. Remove migration-related entries from model caboose jsonkeys
#
module Onetime
  module Models
    module Features
      module WithMigrationFields
        Familia::Base.add_feature self, :with_migration_fields

        # Migration status values
        MIGRATION_STATUS = {
          pending: 'pending',       # Not yet migrated
          in_progress: 'migrating', # Currently being migrated
          completed: 'completed',   # Successfully migrated
          failed: 'failed',         # Migration failed
          skipped: 'skipped',       # Intentionally skipped
        }.freeze

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.extend ClassMethods
          base.include InstanceMethods

          # Migration tracking fields
          base.field :v1_identifier      # Original v1 key/identifier for rollback reference
          base.field :migration_status   # pending, migrating, completed, failed, skipped
          base.field :migrated_at        # Timestamp of migration completion

          # Complete original record storage for rollback/audit
          # Stores both the main object hash and any related data_types
          # (hashkeys, strings, lists, etc.) that were migrated.
          #
          # Structure:
          # {
          #   "object": { ...original hash fields... },
          #   "data_types": {
          #     "brand": { ...hashkey data... },
          #     "logo": "string value",
          #     "sessions": ["list", "items"]
          #   },
          #   "key": "original:redis:key",
          #   "db": 6,
          #   "exported_at": "2026-01-25T01:24:40Z"
          # }
          base.jsonkey :_original_record
        end

        module ClassMethods
          # Find records that need migration
          #
          # @param status [Symbol, String] Migration status to filter by (default: :pending)
          # @return [Array<Familia::Horreum>] Records matching the status
          def pending_migration(status = :pending)
            status_value = MIGRATION_STATUS[status.to_sym] || status.to_s
            instances.revrangeraw(0, -1).collect do |identifier|
              record = load(identifier)
              record if record&.migration_status == status_value
            end.compact
          end

          # Count records by migration status
          #
          # @return [Hash] Counts keyed by status
          def migration_stats
            stats = Hash.new(0)
            instances.revrangeraw(0, -1).each do |identifier|
              record         = load(identifier)
              status         = record&.migration_status || 'pending'
              stats[status] += 1
            end
            stats
          end
        end

        module InstanceMethods
          # Mark record as migrated
          #
          # @param v1_id [String] Original v1 identifier for reference
          # @return [Boolean] Save result
          def mark_migrated!(v1_id = nil)
            self.v1_identifier    = v1_id if v1_id
            self.migration_status = MIGRATION_STATUS[:completed]
            self.migrated_at      = Time.now.to_f.to_s
            save
          end

          # Mark record as migration failed
          #
          # @param error [String, Exception] Error message or exception
          # @return [Boolean] Save result
          def mark_migration_failed!(error = nil)
            self.migration_status = MIGRATION_STATUS[:failed]
            if error
              caboose_data                        = caboose_hash || {}
              caboose_data['migration_error']     = error.is_a?(Exception) ? error.message : error.to_s
              caboose_data['migration_failed_at'] = Time.now.to_f
              self.caboose                        = caboose_data.to_json
            end
            save
          end

          # Check if record has been migrated
          #
          # @return [Boolean]
          def migrated?
            migration_status == MIGRATION_STATUS[:completed]
          end

          # Check if migration is pending
          #
          # @return [Boolean]
          def migration_pending?
            migration_status.nil? || migration_status == MIGRATION_STATUS[:pending]
          end

          # Store migration metadata in caboose
          #
          # @param key [String, Symbol] Metadata key
          # @param value [Object] JSON-serializable value
          # @return [Boolean] Save result
          def store_migration_metadata(key, value)
            data                        = caboose_hash || {}
            data['migration']         ||= {}
            data['migration'][key.to_s] = value
            self.caboose                = data.to_json
            save
          end

          # Retrieve migration metadata from caboose
          #
          # @param key [String, Symbol] Metadata key
          # @return [Object, nil] Stored value or nil
          def migration_metadata(key)
            data = caboose_hash
            data&.dig('migration', key.to_s)
          end

          # Store the complete original v1 record for rollback/audit
          #
          # Captures both the main object hash and any related data_types
          # (hashkeys, strings, lists, sets, etc.) from the Familia model.
          #
          # @param object_data [Hash] The main object hash fields
          # @param data_types_data [Hash] Related data_type values keyed by name
          # @param key [String] Original Redis key
          # @param db [Integer] Source database number
          # @param exported_at [String, Time] Export timestamp
          # @return [void]
          def store_original_record(object_data, data_types_data: {}, key: nil, db: nil, exported_at: nil)
            record                 = {
              'object' => object_data,
              'data_types' => data_types_data,
              'key' => key,
              'db' => db,
              'exported_at' => exported_at&.to_s || Time.now.utc.iso8601,
            }
            _original_record.value = record
          end

          # Retrieve the original v1 record
          #
          # @return [Hash, nil] The stored original record or nil
          def original_record
            _original_record.value
          end

          # Retrieve original object fields
          #
          # @return [Hash, nil] The original object hash or nil
          def original_object
            original_record&.dig('object')
          end

          # Retrieve original data_type values
          #
          # @param name [String, Symbol] Data type name (e.g., :brand, :logo)
          # @return [Object, nil] The original data type value or nil
          def original_data_type(name)
            original_record&.dig('data_types', name.to_s)
          end

          # Check if original record is stored
          #
          # @return [Boolean]
          def original_record?
            !_original_record.value.nil?
          end

          # Build data_types snapshot from current model class definition
          #
          # Iterates over the model's registered data_types and captures
          # their current values. Useful for preserving related field data
          # before migration transforms it.
          #
          # @return [Hash] Data type name => value mapping
          def snapshot_data_types
            return {} unless self.class.respond_to?(:data_types)

            snapshot = {}
            self.class.data_types.each do |name, _definition|
              data_type = begin
                            send(name)
              rescue StandardError
                            nil
              end
              next unless data_type

              # Capture value based on data type class
              snapshot[name.to_s] = case data_type
                                    when Familia::HashKey
                                      data_type.to_h
                                    when Familia::SortedSet, Familia::UnsortedSet
                                      data_type.members
                                    when Familia::ListKey
                                      data_type.to_a
                                    when Familia::StringKey, Familia::JsonStringKey
                                      data_type.value
                                    end
            end
            snapshot.compact
          end

          private

          # Parse caboose JSON to hash
          #
          # @return [Hash, nil]
          def caboose_hash
            return nil if caboose.to_s.empty?

            JSON.parse(caboose)
          rescue JSON::ParserError
            nil
          end
        end
      end
    end
  end
end
