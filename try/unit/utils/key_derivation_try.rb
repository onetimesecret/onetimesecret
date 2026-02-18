# try/unit/utils/key_derivation_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::KeyDerivation (HKDF-based key derivation, RFC 5869).
#
# Verifies:
# 1. Deterministic output for same inputs
# 2. Different outputs for different purposes
# 3. Correct output lengths
# 4. Hex and Base64 encoding helpers
# 5. Session subkey derivation
# 6. Error on unknown purpose

require_relative '../../support/test_helpers'
require 'onetime/key_derivation'

KD = Onetime::KeyDerivation

@secret = 'test-secret-minimum-64-bytes-long-for-production-use-but-any-length-works'

## HKDF derivation is deterministic
a = KD.derive(@secret, :session)
b = KD.derive(@secret, :session)
a == b
#=> true

## Different purposes produce different keys
session_key = KD.derive(@secret, :session)
familia_key = KD.derive(@secret, :familia_enc)
session_key != familia_key
#=> true

## Session key is 64 bytes
KD.derive(@secret, :session).bytesize
#=> 64

## Familia encryption key is 32 bytes
KD.derive(@secret, :familia_enc).bytesize
#=> 32

## Identifier key is 32 bytes
KD.derive(@secret, :identifier).bytesize
#=> 32

## derive_hex returns hex string of correct length (familia_enc: 32 bytes = 64 hex chars)
hex = KD.derive_hex(@secret, :familia_enc)
hex.match?(/\A[a-f0-9]{64}\z/)
#=> true

## derive_hex for session returns 128 hex chars (64 bytes)
KD.derive_hex(@secret, :session).length
#=> 128

## derive_base64 returns valid base64 for familia_enc (32 bytes = 44 chars with padding)
b64 = KD.derive_base64(@secret, :familia_enc)
b64.match?(/\A[A-Za-z0-9+\/]+=*\z/) && Base64.strict_decode64(b64).bytesize == 32
#=> true

## Unknown purpose raises ArgumentError
begin
  KD.derive(@secret, :nonexistent)
  false
rescue ArgumentError => e
  e.message.include?('nonexistent')
end
#=> true

## Session subkey derivation is deterministic
a = KD.derive_session_subkey(@secret, 'hmac')
b = KD.derive_session_subkey(@secret, 'hmac')
a == b
#=> true

## Session subkeys for different purposes differ
hmac_key = KD.derive_session_subkey(@secret, 'hmac')
enc_key  = KD.derive_session_subkey(@secret, 'encryption')
hmac_key != enc_key
#=> true

## Session subkey is 64 hex chars (32 bytes)
KD.derive_session_subkey(@secret, 'hmac').length
#=> 64

## Different secrets produce different keys
key_a = KD.derive('secret-a', :familia_enc)
key_b = KD.derive('secret-b', :familia_enc)
key_a != key_b
#=> true

## Custom salt produces different keys than default salt
default_key = KD.derive(@secret, :familia_enc)
custom_key  = KD.derive(@secret, :familia_enc, salt: 'onetimesecret-v2')
default_key != custom_key
#=> true
