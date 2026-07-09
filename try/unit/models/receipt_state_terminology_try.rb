# try/unit/models/receipt_state_terminology_try.rb
#
# frozen_string_literal: true

# These tryouts test the renamed state terminology for Receipt model:
# - viewed -> previewed (receipt's secret link accessed but content not revealed)
# - received -> revealed (receipt's secret content has been displayed)
#
# Receipt maintains new timestamp fields:
# - `previewed` is telemetry-derived (effective_previewed_at): the previewed!
#   state mutation was retired in #3633, so no GET path stamps it; is_previewed
#   and the previewed/viewed safe_dump fields reflect the access timeline
# - `revealed` field stores timestamp when revealed! is called
# - Legacy `viewed` and `received` fields are supported for API backward compat in safe_dump
#
# The secret_identifier is cleared when revealed! is called.

require_relative '../../support/test_models'

OT.boot! :test, true

## Receipt initializes with :new state
receipt = Onetime::Receipt.new state: :new
receipt.state.to_s
#=> 'new'

## state?(:new) predicate returns true for new receipt
receipt = Onetime::Receipt.new state: :new
receipt.state?(:new)
#=> true

## state?(:previewed) predicate returns false for new receipt
receipt = Onetime::Receipt.new state: :new
receipt.state?(:previewed)
#=> false

## state?(:revealed) predicate returns false for new receipt
receipt = Onetime::Receipt.new state: :new
receipt.state?(:revealed)
#=> false

## revealed! transitions from :new to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.state
#=> 'revealed'

## revealed! sets revealed timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.revealed.to_i > 0
#=> true

## revealed! clears secret_identifier
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
original_secret_id = receipt.secret_identifier
receipt.revealed!
[original_secret_id.length > 0, receipt.secret_identifier]
#=> [true, '']

## revealed! guard prevents transition from :burned
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
original_state = receipt.state
receipt.revealed!
receipt.state == original_state
#=> true

## state?(:revealed) returns true after revealed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.state?(:revealed)
#=> true

## safe_dump previewed field is telemetry-derived from the access timeline (#3633)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.record_access_event('secret_get')
dump = receipt.safe_dump
dump.key?(:previewed) && dump[:previewed].to_i > 0
#=> true

## safe_dump includes revealed field
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump.key?(:revealed) && dump[:revealed].to_i > 0
#=> true

## safe_dump viewed field (backward compat - falls back to telemetry-derived previewed)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.record_access_event('secret_get')
dump = receipt.safe_dump
dump.key?(:viewed) && dump[:viewed].to_i > 0
#=> true

## safe_dump includes received field (backward compat - maps from revealed)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump.key?(:received) && dump[:received].to_i > 0
#=> true

## safe_dump is_viewed returns true once the secret link has been accessed (telemetry)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.record_access_event('secret_get')
dump = receipt.safe_dump
dump[:is_viewed]
#=> true

## safe_dump is_received returns true when revealed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump[:is_received]
#=> true

## safe_dump is_revealed returns true when revealed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump[:is_revealed]
#=> true

## Telemetry-derived previewed timestamp survives revealed! (timeline outlives lifecycle, #3633)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.record_access_event('secret_get')
previewed_ts = receipt.effective_previewed_at.to_i
receipt.revealed!
receipt.effective_previewed_at.to_i == previewed_ts
#=> true

## safe_dump is_previewed reflects access telemetry, not lifecycle state (#3633)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.record_access_event('secret_get')
dump = receipt.safe_dump
dump[:is_previewed]
#=> true

# ----------------------------------------------------------------
# burned! transitions (#2619)
# ----------------------------------------------------------------

## burned! transitions from :new to 'burned'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
receipt.state
#=> 'burned'

## burned! sets burned timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
receipt.burned.to_i > 0
#=> true

## burned! clears secret_identifier
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
original = receipt.secret_identifier
receipt.burned!
[original.length > 0, receipt.secret_identifier]
#=> [true, '']

## state?(:burned) returns true after burned!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
receipt.state?(:burned)
#=> true

## burned! guard prevents transition from :revealed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.burned!
receipt.state
#=> 'revealed'

## burned! guard prevents transition from :burned (no double-burn)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
ts = receipt.burned.to_i
receipt.burned!
receipt.burned.to_i == ts
#=> true

# ----------------------------------------------------------------
# orphaned! transitions (#2619)
# ----------------------------------------------------------------

## orphaned! transitions from :new to 'orphaned'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.orphaned!
receipt.state
#=> 'orphaned'

## orphaned! clears secret_identifier
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
original = receipt.secret_identifier
receipt.orphaned!
[original.length > 0, receipt.secret_identifier]
#=> [true, '']

## orphaned! sets updated timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.orphaned!
receipt.updated.to_i > 0
#=> true

## state?(:orphaned) returns true after orphaned!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.orphaned!
receipt.state?(:orphaned)
#=> true

## orphaned! guard prevents transition from :revealed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.orphaned!
receipt.state
#=> 'revealed'

## orphaned! guard prevents transition from :burned
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
receipt.orphaned!
receipt.state
#=> 'burned'

## orphaned! guard requires non-empty secret_identifier
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.secret_identifier = ''
receipt.save
receipt.orphaned!
receipt.state
#=> 'new'

# ----------------------------------------------------------------
# expired! transitions (#2619)
# ----------------------------------------------------------------

## expired! transitions to 'expired' when secret has expired
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 1, 'test secret'
# Force created timestamp far in the past so secret_expired? returns true
receipt.created = (Familia.now.to_i - 3600)
receipt.save
receipt.expired!
receipt.state
#=> 'expired'

## expired! clears secret_identifier and secret_key
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 1, 'test secret'
receipt.created = (Familia.now.to_i - 3600)
receipt.save
receipt.expired!
[receipt.secret_identifier, receipt.secret_key]
#=> ['', '']

## expired! sets updated timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 1, 'test secret'
receipt.created = (Familia.now.to_i - 3600)
receipt.save
receipt.expired!
receipt.updated.to_i > 0
#=> true

## state?(:expired) returns true after expired!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 1, 'test secret'
receipt.created = (Familia.now.to_i - 3600)
receipt.save
receipt.expired!
receipt.state?(:expired)
#=> true

## expired! guard prevents transition when secret has not expired
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 86400, 'test secret'
receipt.expired!
receipt.state
#=> 'new'

# ----------------------------------------------------------------
# Sequential lifecycle chains (#2619)
# ----------------------------------------------------------------

## Terminal state: burned rejects all further transitions
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
receipt.revealed!
receipt.orphaned!
receipt.state
#=> 'burned'

## Terminal state: revealed rejects all further transitions
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
receipt.burned!
receipt.orphaned!
receipt.state
#=> 'revealed'
