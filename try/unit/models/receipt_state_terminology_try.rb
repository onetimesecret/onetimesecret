# try/unit/models/receipt_state_terminology_try.rb
#
# frozen_string_literal: true

# These tryouts test the renamed state terminology for Receipt model:
# - viewed -> previewed (receipt's secret link accessed but content not revealed)
# - received -> revealed (receipt's secret content has been displayed)
#
# Receipt maintains new timestamp fields:
# - `previewed` field stores timestamp when previewed! is called
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

## previewed! transitions from :new to 'previewed' and sets timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
[receipt.state, receipt.previewed.to_i > 0]
#=> ['previewed', true]

## previewed! guard prevents transition from non-new states
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.burned!
original_state = receipt.state
receipt.previewed!
receipt.state == original_state
#=> true

## state?(:previewed) returns true after previewed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
receipt.state?(:previewed)
#=> true

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

## revealed! transitions from :previewed to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
receipt.revealed!
receipt.state
#=> 'revealed'

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

## safe_dump includes previewed field
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
dump = receipt.safe_dump
dump.key?(:previewed) && dump[:previewed].to_i > 0
#=> true

## safe_dump includes revealed field
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump.key?(:revealed) && dump[:revealed].to_i > 0
#=> true

## safe_dump includes viewed field (backward compat - maps from previewed)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
dump = receipt.safe_dump
dump.key?(:viewed) && dump[:viewed].to_i > 0
#=> true

## safe_dump includes received field (backward compat - maps from revealed)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.revealed!
dump = receipt.safe_dump
dump.key?(:received) && dump[:received].to_i > 0
#=> true

## safe_dump is_viewed returns true when previewed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
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

## Previewed then revealed preserves previewed timestamp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
previewed_ts = receipt.previewed.to_i
receipt.revealed!
receipt.previewed.to_i == previewed_ts
#=> true

## safe_dump is_previewed returns true when previewed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
receipt.previewed!
dump = receipt.safe_dump
dump[:is_previewed]
#=> true
