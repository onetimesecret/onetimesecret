# lib/onetime/models/customer/chores/reserialize_fields.rb
#
# frozen_string_literal: true

# Housekeeping chore: Resave legacy customers whose field values are
# stored as bare strings rather than Familia v2 JSON-encoded values.
#
# Familia v2 wraps every scalar in JSON before writing to Redis
# (e.g. "alice@example.com" → "\"alice@example.com\""). Records
# created before the migration store bare strings, which trigger
# "Legacy plain string in Onetime::Customer#email" on every load.
#
# Detection: HGETALL the raw hash from Redis and check whether
# every present value already looks like valid JSON. If all do,
# skip. Otherwise the fields holding legacy plain strings (values that
# are not JSON at all) are rewritten with `save_fields`, from the bytes
# just read, leaving every other field as it is in Redis.
#
# A bare number (`created`, `updated`, counters) passes the "bare" test
# too, but it is already what v2 writes, so it is never rewritten; the
# record is still reported as modified, as it always has been.
#
# Safe to run repeatedly — already-migrated records are skipped.
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Customer', :reserialize_fields)

module Onetime
  module Chores
    module ReserializeFields
      # A legacy plain string is a stored value that does not parse as JSON
      # (v2 JSON-encodes every scalar; a bare number still parses).
      def self.legacy_plain_string?(value)
        JSON.parse(value)
        false
      rescue JSON::ParserError
        true
      end
    end
  end
end

Onetime::Customer.chore :reserialize_fields do |cust|
  logger    = Onetime.get_logger('Chores')
  raw_hash  = cust.hgetall
  json_lits = %w[true false null].freeze

  bare_fields = raw_hash.filter_map do |field, val|
    next if val.nil? || val.empty?
    next if val.start_with?('{', '[', '"') || json_lits.include?(val)

    field
  end

  next if bare_fields.empty?

  # Rewrite only the legacy plain strings, from the bytes the HGETALL above
  # just read. HousekeepingJob loads customers in batches, so `cust` can be
  # minutes old by now; a full `save` would write that stale copy of every
  # field back over edits made since (an on-demand console run, #4343, can
  # land mid-business-day). Undeclared fields are skipped, as `save` skipped
  # them. A partial write leaves `updated` alone: re-encoding is not an edit.
  declared = Onetime::Customer.persistent_fields.map(&:to_s)
  legacy   = bare_fields.select do |field|
    declared.include?(field) && Onetime::Chores::ReserializeFields.legacy_plain_string?(raw_hash[field])
  end

  logger.info 'Reserializing legacy plain-string fields',
    chore: :reserialize_fields,
    cust_extid: cust.extid,
    fields: legacy

  unless legacy.empty?
    # The loaded value of a legacy string is the raw string itself.
    legacy.each { |field| cust.public_send(:"#{field}=", raw_hash[field]) }
    cust.save_fields(*legacy.map(&:to_sym))
  end
  true
end
