# try/api/v1/receipt_hsh_state_translation_try.rb
#
# frozen_string_literal: true

# Tests for V1 API state translation in receipt_hsh (issue #2619).
#
# The v0.24 state machine uses new state names that differ from the v0.23.4
# vocabulary that V1 API clients expect. The receipt_hsh method translates
# these back for backward compatibility:
#
#   previewed -> viewed
#   revealed  -> received
#   shared    -> new
#
# States that existed in v0.23.4 pass through unchanged:
#   new, burned, expired, orphaned
#
# Additionally, share_domain must return "" (empty string) when not set,
# never nil/null.

require_relative '../../support/test_models'

require 'v1/controllers'

OT.boot! :test, false

@receipt, @secret = Onetime::Receipt.spawn_pair 'anon', 300, 'secret message'

## TC-1: previewed state translates to viewed
@receipt.state = 'previewed'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'viewed'

## TC-2: revealed state translates to received
@receipt.state = 'revealed'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'received'

## TC-3: shared state translates to new
@receipt.state = 'shared'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'new'

## TC-4: new state passes through unchanged
@receipt.state = 'new'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'new'

## TC-5: burned state passes through unchanged
@receipt.state = 'burned'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'burned'

## TC-6: expired state passes through unchanged
@receipt.state = 'expired'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'expired'

## TC-7: orphaned state passes through unchanged
@receipt.state = 'orphaned'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['state']
#=> 'orphaned'

## TC-8: revealed state deletes secret_key and secret_ttl (translated to received)
@receipt.state = 'revealed'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt, secret_ttl: 1800)
[result.key?('secret_key'), result.key?('secret_ttl'), result.key?('received')]
#=> [false, false, true]

## TC-9: share_domain returns empty string when not set
@receipt.share_domain = nil
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['share_domain']
#=> ''

## TC-10: no v0.24-only state values appear in receipt_hsh output
v024_only_states = %w[previewed revealed shared]
all_states = %w[previewed revealed shared new burned expired orphaned]
translated = all_states.map do |s|
  @receipt.state = s
  @receipt.save
  V1::Controllers::Index.receipt_hsh(@receipt)['state']
end
translated.none? { |s| v024_only_states.include?(s) }
#=> true

## TC-11: V1_STATE_MAP constant is accessible and frozen
[V1::Controllers::ClassMethods::V1_STATE_MAP.frozen?, V1::Controllers::ClassMethods::V1_STATE_MAP.size]
#=> [true, 3]

## TC-12: translate_v1_state method maps known states and passes through unknown ones
[V1::Controllers::Index.translate_v1_state('previewed'), V1::Controllers::Index.translate_v1_state('burned')]
#=> ['viewed', 'burned']

## TC-13: custid falls back to 'anon' for anonymous secrets
@receipt.custid = nil
@receipt.v1_custid = nil
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['custid']
#=> 'anon'

## TC-14: received timestamp falls back to revealed field
now_ts = Time.now.to_i
@receipt.received = nil
@receipt.revealed = now_ts
@receipt.state = 'revealed'
@receipt.save
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['received'] == now_ts
#=> true

## TC-15: Sequential lifecycle new→previewed→revealed never leaks v0.24 states
v024_only = %w[previewed revealed shared]
@lifecycle_receipt, @lifecycle_secret = Onetime::Receipt.spawn_pair 'anon', 300, 'lifecycle test'
# Step 1: initial state after creation (new)
step1 = V1::Controllers::Index.receipt_hsh(@lifecycle_receipt)['state']
# Step 2: after previewed! transition
@lifecycle_receipt.previewed!
step2 = V1::Controllers::Index.receipt_hsh(@lifecycle_receipt)['state']
# Step 3: after revealed! transition
@lifecycle_receipt.revealed!
step3 = V1::Controllers::Index.receipt_hsh(@lifecycle_receipt)['state']
states = [step1, step2, step3]
[states, states.none? { |s| v024_only.include?(s) }]
#=> [['new', 'viewed', 'received'], true]

## TC-16: Sequential lifecycle new→previewed→burned never leaks v0.24 states
v024_only = %w[previewed revealed shared]
@burn_receipt, @burn_secret = Onetime::Receipt.spawn_pair 'anon', 300, 'burn lifecycle test'
step1b = V1::Controllers::Index.receipt_hsh(@burn_receipt)['state']
@burn_receipt.previewed!
step2b = V1::Controllers::Index.receipt_hsh(@burn_receipt)['state']
@burn_receipt.burned!
step3b = V1::Controllers::Index.receipt_hsh(@burn_receipt)['state']
burn_states = [step1b, step2b, step3b]
[burn_states, burn_states.none? { |s| v024_only.include?(s) }]
#=> [['new', 'viewed', 'burned'], true]

# Teardown
@lifecycle_receipt.destroy!
@lifecycle_secret.destroy!
@burn_receipt.destroy!
@burn_secret.destroy!
@receipt.destroy!
@secret.destroy!
