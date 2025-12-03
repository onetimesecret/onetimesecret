# .purgatory/migrations/core/20250728-1512_00_customer_objid.rb
#
# frozen_string_literal: true

#
# Customer Object ID (and External ID) Migration - Pipeline
#
# Purpose: Populates objid field for all existing Customer records. The extid
#   field will be lazy populated on first access.
# - objid: Set to a UUIDv7 based on the customer's created timestamp
# - extid: Set to a base36 encoded random string, using the same approach as
#   familia v2.0.0-pre12.
#
# Usage:
#   bin/ots migrate 20250728-1512_00_customer_objid.rb # Preview changes
#   bin/ots migrate --run 20250728-1512_00_customer_objid.rb
#
#   ruby -I./lib migrate/20250728-1512_00_customer_objid.rb --dry-run  # Preview changes
#   ruby -I./lib migrate/20250728-1512_00_customer_objid.rb --run
#

require 'onetime/migration'
require 'onetime/refinements/uuidv7_refinements'

module Onetime
  class Migration < PipelineMigration
    using Onetime::UUIDv7Refinements

    def prepare
      @model_class = Onetime::Customer
      @batch_size  = 100  # Smaller batches for pipeline
    end

    def should_process?(obj)
      return track_stat(:skipped_empty_custid) if obj.custid.to_s.empty?
      return track_stat(:skipped_empty_email) if obj.email.to_s.empty?
      return track_stat(:skipped_user_deleted_self) if obj.user_deleted_self?
      return track_stat(:skipped_tryouts_test_record) if obj.email.to_s.start_with?('tryouts+')
      return track_stat(:skipped_empty_created) if obj.created.to_s.empty?

      true
    end

    def build_update_fields(obj)
      # Generate or use existing objid
      new_objid = obj.objid || SecureRandom.uuid_v7_from(obj.created)

      {
        # We take a page from Django's book here by not relying on model
        # methods or attributes that could be changed in ways we don't
        # expect (e.g. like when they're removed entirely).
        objid: new_objid,
        extid: obj.extid || Tools.derive_extid_from_uuid(new_objid),
      }
    end
  end
end

module Tools
  require 'digest'
  require 'securerandom'

  # A standalone implementation of the logic that Familia v2.0.0-pre12 uses
  # to derive an external ID from a UUIDv7. We use this separate implementation
  # to allow this migration to transcend time and space.
  def self.derive_extid_from_uuid(uuid_string, prefix: 'ext')
    # Normalize UUID to hex (remove hyphens)
    normalized_hex = uuid_string.delete('-')

    # Create seed from the hex string
    seed = Digest::SHA256.digest(normalized_hex)

    # Initialize PRNG with the seed
    prng = Random.new(seed.unpack1('Q>'))

    # Generate 16 bytes of deterministic output
    random_bytes = prng.bytes(16)

    # Encode as base36 string
    external_part = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')

    "#{prefix}_#{external_part}"
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
