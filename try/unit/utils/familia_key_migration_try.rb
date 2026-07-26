# try/unit/utils/familia_key_migration_try.rb
#
# frozen_string_literal: true

# Verifies the Familia encryption keyset after the C6 retirement of the
# legacy v1 (unsalted SHA-256) decrypt fallback. The v1→v2 migration is
# complete: no v1-tagged ciphertext survives the secret TTL window, so the
# weaker root-secret-derived key is no longer registered. Verifies:
#
# 1. v2 (HKDF) key is present
# 2. v1 (legacy SHA-256) key is NOT present
# 3. current_key_version is :v2
# 4. v2 key matches the HKDF derivation
#
# See docs/security/assessment-2026-06-22/resolutions/C6-*.md.

require_relative '../../support/test_helpers'
require 'onetime/key_derivation'

OT.boot! :test, false

CF = Onetime::Initializers::ConfigureFamilia

@secret_key = OT.conf.dig('site', 'secret')

# ConfigureFamilia is skipped when connect_to_db=false, so build the keyset
# through the production pure mapping to test the derivation logic in isolation.
keys, current_version              = CF.build_encryption_keys(@secret_key, nil)
Familia.config.encryption_keys     = keys
Familia.config.current_key_version = current_version

## v2 (HKDF) key is present
Familia.config.encryption_keys.key?(:v2)
#=> true

## v1 (legacy unsalted SHA-256) key has been retired — not registered
Familia.config.encryption_keys.key?(:v1)
#=> false

## current_key_version is :v2
Familia.config.current_key_version
#=> :v2

## v2 key matches HKDF derivation
expected_v2 = Onetime::KeyDerivation.derive_base64(@secret_key, :familia_enc)
Familia.config.encryption_keys[:v2] == expected_v2
#=> true
