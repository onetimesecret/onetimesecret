# try/unit/models/secret_state_terminology_try.rb
#
# frozen_string_literal: true

# These tryouts test the renamed state terminology for Secret model:
# - viewed -> previewed (secret link accessed but content not yet revealed)
# - received -> revealed (secret content has been displayed to recipient)
#
# This terminology rename improves clarity:
# - "previewed" better describes accessing the secret link page
# - "revealed" better describes the action of displaying the secret content
#
# The old terminology is maintained for backward compatibility in safe_dump.
#
# NOTE (#3633): the previewed! state mutation was retired. No request path
# advances a Secret to :previewed anymore; :previewed survives only as a
# backward-compat guard term for pre-#3633 data. Cases that exercised the
# previewed! transition/state were dropped here.

require_relative '../../support/test_models'

OT.boot! :test, true

## Secret initializes with :new state
secret = Onetime::Secret.new state: :new
secret.state.to_s
#=> 'new'

## state?(:new) predicate returns true for new secret
secret = Onetime::Secret.new state: :new
secret.state?(:new)
#=> true

## state?(:previewed) predicate returns false for new secret
secret = Onetime::Secret.new state: :new
secret.state?(:previewed)
#=> false

## state?(:revealed) predicate returns false for new secret
secret = Onetime::Secret.new state: :new
secret.state?(:revealed)
#=> false

## revealed! transitions from :new to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.state
#=> 'revealed'

## revealed! guard prevents transition from :revealed
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.revealed!
secret.state
#=> 'revealed'

## state?(:revealed) returns true after revealed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.state?(:revealed)
#=> true

## viewable? returns true for :new state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.state?(:new) && secret.viewable?
#=> true

## viewable? returns false for :revealed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.viewable?
#=> false

## receivable? returns true for :new state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.receivable?
#=> true

## receivable? returns false for :revealed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.receivable?
#=> false

## safe_dump is_revealed returns true after revealed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
dump = secret.safe_dump
dump[:is_revealed]
#=> true

## safe_dump is_received returns true when revealed (backward compat)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
dump = secret.safe_dump
dump[:is_received]
#=> true

# ----------------------------------------------------------------
# burned! transitions (#2619)
# ----------------------------------------------------------------

## burned! from :new does not update secret state (secret is destroyed instead)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
original_state = secret.state
secret.burned!
secret.state == original_state
#=> true

## burned! from :new destroys the secret in Redis
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.burned!
secret.exists?
#=> false

## burned! from :new transitions receipt to 'burned'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.burned!
Onetime::Receipt.load(receipt.identifier).state
#=> 'burned'

## burned! clears passphrase_temp
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.instance_variable_set(:@passphrase_temp, 'temp_pass')
secret.burned!
secret.instance_variable_get(:@passphrase_temp).nil?
#=> true

## burned! guard prevents burn from :revealed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
receipt_state_before = Onetime::Receipt.load(receipt.identifier).state
secret.burned!
Onetime::Receipt.load(receipt.identifier).state == receipt_state_before
#=> true

## viewable? returns false after burned! (secret destroyed from Redis)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
before = secret.viewable?
secret.burned!
[before, secret.viewable?]
#=> [true, false]

## receivable? returns false after burned! (secret destroyed from Redis)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
before = secret.receivable?
secret.burned!
[before, secret.receivable?]
#=> [true, false]

# ----------------------------------------------------------------
# revealed! cascades to receipt (#2619)
# ----------------------------------------------------------------

## revealed! from :new transitions receipt to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
Onetime::Receipt.load(receipt.identifier).state
#=> 'revealed'

## revealed! clears @value and @ciphertext
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
[secret.instance_variable_get(:@value), secret.instance_variable_get(:@ciphertext)]
#=> [nil, nil]

# ----------------------------------------------------------------
# Sequential lifecycle chains (#2619)
# ----------------------------------------------------------------

## new → burned chain (receipt reflects burn)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
s1 = secret.state
secret.burned!
r_state = Onetime::Receipt.load(receipt.identifier).state
[s1, r_state]
#=> ['new', 'burned']

## After revealed!, further transitions are no-ops (state stays 'revealed')
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.burned!
secret.state
#=> 'revealed'

## revealed! destroys the secret in Redis
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.exists?
#=> false
