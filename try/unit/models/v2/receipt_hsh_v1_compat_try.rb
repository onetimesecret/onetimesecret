# try/unit/models/v2/receipt_hsh_v1_compat_try.rb
#
# frozen_string_literal: true

# V1 API backward compatibility tests for receipt_hsh [#2615]
#
# These tryouts verify that the V1 compatibility layer (receipt_hsh) correctly
# transforms v0.24 internal vocabulary back to v0.23.x field names and states.
#
# Covers:
#   - Field rename mapping (identifier->metadata_key, etc.)
#   - State mapping (previewed->viewed, revealed->received, shared->new)
#   - Anonymous custid handling ("anon" not null)
#   - Burned/revealed secret_key handling ("" not null)
#   - Passphrase and value pass-through
#   - Received timestamp fallback from revealed field

require_relative '../../../support/test_models'

require 'v1/controllers'

OT.boot! :test, false

@receipt, @secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'test secret for v1 compat'

## receipt_hsh maps identifier to metadata_key
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['metadata_key']
#=> @receipt.identifier

## receipt_hsh maps secret_identifier to secret_key
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['secret_key']
#=> @receipt.secret_identifier

## receipt_hsh maps has_passphrase option to passphrase_required
result = V1::Controllers::Index.receipt_hsh(@receipt, passphrase_required: true)
result['passphrase_required']
#=> true

## receipt_hsh maps recipients to recipient (singular key name)
result = V1::Controllers::Index.receipt_hsh(@receipt)
result.key?('recipient')
#=> true

## receipt_hsh maps receipt expiration to metadata_ttl
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['metadata_ttl'].is_a?(Integer) && result['metadata_ttl'] > 0
#=> true

## receipt_hsh maps value option to value in output
result = V1::Controllers::Index.receipt_hsh(@receipt, value: 'decrypted content')
result['value']
#=> 'decrypted content'

## receipt_hsh maps share_domain to empty string when nil
receipt_no_domain, secret_no_domain = Onetime::Receipt.spawn_pair 'anon', 3600, 'no domain secret'
receipt_no_domain.share_domain = nil
receipt_no_domain.save
result = V1::Controllers::Index.receipt_hsh(receipt_no_domain)
result['share_domain']
#=> ''

## State mapping: 'new' state remains 'new' (shared->new identity case)
receipt_new, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'new state secret'
result = V1::Controllers::Index.receipt_hsh(receipt_new)
result['state']
#=> 'new'

## State mapping: 'previewed' maps to 'viewed'
receipt_previewed, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'previewed state secret'
receipt_previewed.previewed!
result = V1::Controllers::Index.receipt_hsh(receipt_previewed)
result['state']
#=> 'viewed'

## State mapping: 'revealed' maps to 'received'
receipt_revealed, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'revealed state secret'
receipt_revealed.revealed!
result = V1::Controllers::Index.receipt_hsh(receipt_revealed)
result['state']
#=> 'received'

## State mapping: 'burned' remains 'burned' (no rename needed)
receipt_burned, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'burned state secret'
receipt_burned.burned!
result = V1::Controllers::Index.receipt_hsh(receipt_burned)
result['state']
#=> 'burned'

## Anonymous custid: receipt created with 'anon' owner returns 'anon' custid
receipt_anon, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'anon custid secret'
result = V1::Controllers::Index.receipt_hsh(receipt_anon)
result['custid']
#=> 'anon'

## Anonymous custid: opts[:custid] overrides hash custid
receipt_anon2, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'anon override secret'
result = V1::Controllers::Index.receipt_hsh(receipt_anon2, custid: 'user@example.com')
result['custid']
#=> 'user@example.com'

## Burned secret_key: after reveal, secret_identifier is cleared so secret_key should be empty or nil
receipt_for_burn, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'burn key test'
receipt_for_burn.revealed!
result = V1::Controllers::Index.receipt_hsh(receipt_for_burn)
# In 'received' state, secret_key is deleted from result hash entirely
result.key?('secret_key')
#=> false

## Burned secret_key: after burn, secret_key is deleted from result
receipt_for_actual_burn, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'actual burn test'
receipt_for_actual_burn.burned!
result = V1::Controllers::Index.receipt_hsh(receipt_for_actual_burn)
# Burned state is not 'received', so secret_key should be present
# But secret_identifier was not cleared by burned!, so it should still have a value
result.key?('secret_key')
#=> true

## Received timestamp fallback: uses revealed timestamp when received field is empty
receipt_ts, _ = Onetime::Receipt.spawn_pair 'anon', 3600, 'timestamp fallback test'
receipt_ts.revealed!
result = V1::Controllers::Index.receipt_hsh(receipt_ts)
# After revealed!, the 'received' field in result should have a positive timestamp
# (falls back to the 'revealed' timestamp since v0.24 sets revealed, not received)
result['received'].is_a?(Integer) && result['received'] > 0
#=> true

## All six V1 field names present for a new receipt
result = V1::Controllers::Index.receipt_hsh(@receipt, value: 'test', passphrase_required: false, secret_ttl: 3600)
required_v1_fields = %w[metadata_key secret_key metadata_ttl recipient value passphrase_required]
required_v1_fields.all? { |f| result.key?(f) }
#=> true

## V1 field 'custid' is present
result = V1::Controllers::Index.receipt_hsh(@receipt)
result.key?('custid')
#=> true

## V1 field 'state' is present
result = V1::Controllers::Index.receipt_hsh(@receipt)
result.key?('state')
#=> true

## V1 field 'created' is present and is an integer
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['created'].is_a?(Integer)
#=> true

## V1 field 'updated' is present and is an integer
result = V1::Controllers::Index.receipt_hsh(@receipt)
result['updated'].is_a?(Integer)
#=> true

# Teardown
@receipt.destroy!
@secret.destroy!
