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

# Teardown
@receipt.destroy!
@secret.destroy!
