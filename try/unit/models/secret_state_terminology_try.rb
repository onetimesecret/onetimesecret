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

## previewed! transitions from :new to 'previewed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
secret.state
#=> 'previewed'

## previewed! guard prevents transition from :previewed (idempotent)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
first_state = secret.state
secret.previewed!
[first_state, secret.state]
#=> ['previewed', 'previewed']

## state?(:previewed) returns true after previewed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
secret.state?(:previewed)
#=> true

## revealed! transitions from :new to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.state
#=> 'revealed'

## revealed! transitions from :previewed to 'revealed'
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
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

## viewable? returns true for :previewed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
secret.viewable?
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

## receivable? returns true for :previewed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
secret.receivable?
#=> true

## receivable? returns false for :revealed state
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
secret.receivable?
#=> false

## safe_dump is_previewed returns true after previewed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
dump = secret.safe_dump
dump[:is_previewed]
#=> true

## safe_dump is_revealed returns true after revealed!
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
dump = secret.safe_dump
dump[:is_revealed]
#=> true

## safe_dump is_viewed returns true when previewed (backward compat)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.previewed!
dump = secret.safe_dump
dump[:is_viewed]
#=> true

## safe_dump is_received returns true when revealed (backward compat)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret'
secret.revealed!
dump = secret.safe_dump
dump[:is_received]
#=> true
