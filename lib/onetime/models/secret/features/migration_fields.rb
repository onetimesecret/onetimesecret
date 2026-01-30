# lib/onetime/models/secret/features/migration_fields.rb
#
# frozen_string_literal: true

# Secret Migration Feature
#
# Adds Secret-specific migration fields and methods for v1 → v2 migration.
# This feature should be removed after migration is complete.
#
# v1 → v2 CHANGES:
# - custid (email or 'anon') → owner_id (Customer objid or 'anon')
# - Remove: original_size field (dropped in v2)
# - Encryption: Preserve exact values (do NOT re-encrypt)
#   - value_encryption: -1 (empty), 0 (none), 1 (v1), 2 (v2)
#   - passphrase_encryption: 1 (bcrypt), 2 (argon2id)
#
# REMOVAL: See lib/onetime/models/features/with_migration_fields.rb
#
module Onetime::Secret::Features
  module MigrationFields
    Familia::Base.add_feature self, :secret_migration_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Original v1 identifiers for reference/rollback
      base.field :v1_custid       # Original email-based custid or 'anon'
      base.field :v1_original_size # Dropped field, kept for reference only
    end

    module ClassMethods
      # Find secrets that need owner_id migration
      #
      # @return [Array<Secret>]
      def pending_owner_migration
        instances.revrangeraw(0, -1).collect do |identifier|
          secret = load(identifier)
          secret if secret&.v1_custid.to_s.present? && secret.owner_id.to_s.empty?
        end.compact
      end

      # Count secrets by encryption version
      #
      # @return [Hash] { version => count }
      def encryption_stats
        stats = Hash.new(0)
        instances.revrangeraw(0, -1).each do |identifier|
          secret = load(identifier)
          next unless secret

          version         = secret.value_encryption.to_s
          version         = 'none' if version.empty?
          stats[version] += 1
        end
        stats
      end

      # Count anonymous vs authenticated secrets
      #
      # @return [Hash] { anonymous: count, authenticated: count }
      def ownership_stats
        stats = { anonymous: 0, authenticated: 0 }
        instances.revrangeraw(0, -1).each do |identifier|
          secret = load(identifier)
          next unless secret

          custid = secret.v1_custid || secret.owner_id
          if custid.to_s == 'anon' || custid.to_s.empty?
            stats[:anonymous] += 1
          else
            stats[:authenticated] += 1
          end
        end
        stats
      end
    end

    module InstanceMethods
      # Migrate custid to owner_id using customer email → objid lookup
      #
      # IMPORTANT: Does NOT re-encrypt the secret value. Encryption is preserved exactly.
      #
      # @param email_to_objid_mapping [Hash] email => customer_objid mapping
      # @return [Boolean] Success status
      def migrate_owner!(email_to_objid_mapping)
        return true if owner_id.to_s.present? # Already migrated

        custid = v1_custid
        return false if custid.to_s.empty?

        # Handle anonymous
        if custid == 'anon'
          self.owner_id         = 'anon'
          self.migration_status = 'completed'
          self.migrated_at      = Time.now.to_f.to_s
          return save
        end

        # Look up customer objid
        customer_objid = email_to_objid_mapping[custid]
        unless customer_objid
          OT.le '[Secret.migrate_owner!] No customer found',
            { secret: identifier, v1_custid: custid }
          return false
        end

        self.owner_id         = customer_objid
        self.migration_status = 'completed'
        self.migrated_at      = Time.now.to_f.to_s
        save
      end

      # Store dropped original_size field for reference
      #
      # The original_size field was removed in v2. This method preserves
      # the value in migration fields for reference but does not set it
      # on the main object.
      #
      # @param size [String, Integer] Original size value from v1
      # @return [Boolean] Save result
      def preserve_original_size(size)
        self.v1_original_size = size.to_s
        save
      end

      # Check if secret needs owner migration
      #
      # @return [Boolean]
      def needs_owner_migration?
        v1_custid.to_s.present? && owner_id.to_s.empty?
      end

      # Check if secret is from anonymous user
      #
      # @return [Boolean]
      def anonymous_secret?
        owner_id.to_s == 'anon' || v1_custid.to_s == 'anon'
      end

      # Check encryption version
      #
      # @return [Symbol] :empty, :none, :v1, :v2
      def encryption_version
        case value_encryption.to_s
        when '-1' then :empty
        when '0' then :none
        when '1' then :v1
        when '2' then :v2
        else :unknown
        end
      end
    end
  end
end
