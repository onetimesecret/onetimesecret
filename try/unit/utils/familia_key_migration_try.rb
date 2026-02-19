# try/unit/utils/familia_key_migration_try.rb
#
# frozen_string_literal: true

# Tests that Familia encryption key migration from v1 (SHA-256) to
# v2 (HKDF) is correctly configured. Verifies:
#
# 1. Both v1 and v2 keys are present in Familia config
# 2. v1 and v2 keys are different (distinct derivation methods)
# 3. current_key_version is :v2
# 4. v1 key matches the legacy SHA-256 derivation
# 5. v2 key matches the HKDF derivation

require_relative '../../support/test_helpers'
require 'onetime/key_derivation'

OT.boot! :test, false

@secret_key = OT.conf.dig('site', 'secret')

## Familia has both v1 and v2 encryption keys
keys = Familia.config.encryption_keys
keys.key?(:v1) && keys.key?(:v2)
#=> true

## current_key_version is :v2
Familia.config.current_key_version
#=> :v2

## v1 and v2 keys are different
keys = Familia.config.encryption_keys
keys[:v1] != keys[:v2]
#=> true

## v1 key matches legacy SHA-256 derivation
expected_v1 = Base64.strict_encode64(Digest::SHA256.digest(@secret_key))
Familia.config.encryption_keys[:v1] == expected_v1
#=> true

## v2 key matches HKDF derivation
expected_v2 = Onetime::KeyDerivation.derive_base64(@secret_key, :familia_enc)
Familia.config.encryption_keys[:v2] == expected_v2
#=> true
