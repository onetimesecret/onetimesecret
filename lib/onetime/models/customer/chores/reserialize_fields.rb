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
# skip. If any bare string remains, a `save` round-trips every
# persistent field through `serialize_value`, fixing the entire
# record in one HMSET.
#
# Safe to run repeatedly — already-migrated records are skipped.
#
# Run via HousekeepingJob:
#   HousekeepingJob.perform('Onetime::Customer', :reserialize_fields)

module Onetime
  module Chores
    module ReserializeFields
    end
  end
end

Onetime::Customer.chore :reserialize_fields do |cust|
  logger    = Onetime.get_logger('Chores')
  raw_hash  = cust.hgetall
  json_lits = %w[true false null].freeze

  needs_resave = raw_hash.any? do |_field, val|
    next false if val.nil? || val.empty?
    next false if val.start_with?('{', '[', '"') || json_lits.include?(val)

    true
  end

  next unless needs_resave

  logger.info 'Reserializing legacy plain-string fields',
    chore: :reserialize_fields,
    cust_extid: cust.extid

  cust.save
  true
end
