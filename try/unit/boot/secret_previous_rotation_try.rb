# try/unit/boot/secret_previous_rotation_try.rb
#
# frozen_string_literal: true

# SECRET_PREVIOUS rotation chain (C10 §3.3).
#
# ConfigureFamilia.build_encryption_keys is the pure mapping behind Familia's
# encryption_keys/current_key_version configuration:
#
#   - no SECRET_PREVIOUS: byte-identical to the pre-C10 config (v1 legacy
#     SHA-256 + v2 HKDF from the current SECRET, writes tagged :v2).
#   - SECRET_PREVIOUS set (oldest first): :v1/:v2 map to the OLDEST previous
#     secret (every v1/v2 envelope predates the first rotation), every
#     previous secret registers decrypt-only under its content-addressed tag,
#     and the current SECRET's content tag becomes the tag for new writes.
#
# The final cases prove the §3.3 implementation checkpoint against the real
# encryption path: familia round-trips arbitrary version symbols in
# envelopes, so an envelope written before a rotation still decrypts after
# the keys are re-registered under the rotated mapping.

require_relative '../../support/test_models'

OT.boot! :test, true

CF = Onetime::Initializers::ConfigureFamilia

@secret_old = 'old-root-secret-that-wrote-all-the-existing-envelopes'
@secret_mid = 'middle-generation-secret-from-the-first-rotation'
@secret_new = 'current-root-secret-after-the-latest-rotation'

## No SECRET_PREVIOUS: byte-identical legacy mapping, writes tagged :v2
keys, current = CF.build_encryption_keys(@secret_new, nil)
expected_v1   = Base64.strict_encode64(Digest::SHA256.digest(@secret_new))
expected_v2   = Onetime::KeyDerivation.derive_base64(@secret_new, :familia_enc)
[keys, current] == [{ v1: expected_v1, v2: expected_v2 }, :v2]
#=> true

## Blank/whitespace SECRET_PREVIOUS is treated as unset (compose files inject
## empty strings for unset outer variables)
CF.build_encryption_keys(@secret_new, '  ') == CF.build_encryption_keys(@secret_new, nil)
#=> true

## content_tag is deterministic, content-addressed (r + first 8 hex of the
## :key_verifier derivation), and distinct per secret
tags = [@secret_old, @secret_new].map { |s| CF.content_tag(s) }
[tags == [@secret_old, @secret_new].map { |s| CF.content_tag(s) },
 tags.first != tags.last,
 tags.all? { |t| t.to_s.match?(/\Ar[0-9a-f]{8}\z/) }]
#=> [true, true, true]

## Single rotation: v1/v2 map to the PREVIOUS secret's keys, current writes
## move to the current secret's content tag
keys, current = CF.build_encryption_keys(@secret_new, @secret_old)
[keys[:v1] == Base64.strict_encode64(Digest::SHA256.digest(@secret_old)),
 keys[:v2] == Onetime::KeyDerivation.derive_base64(@secret_old, :familia_enc),
 current == CF.content_tag(@secret_new),
 keys[current] == Onetime::KeyDerivation.derive_base64(@secret_new, :familia_enc)]
#=> [true, true, true, true]

## Multi-rotation chain (oldest first): v1/v2 stay with the OLDEST secret and
## every generation is registered under its own content tag
keys, current = CF.build_encryption_keys(@secret_new, "#{@secret_old}, #{@secret_mid}")
[keys[:v2] == Onetime::KeyDerivation.derive_base64(@secret_old, :familia_enc),
 keys.key?(CF.content_tag(@secret_old)),
 keys.key?(CF.content_tag(@secret_mid)),
 current == CF.content_tag(@secret_new),
 keys.keys.size]
#=> [true, true, true, true, 5]

## CHECKPOINT (design §3.3): an envelope written under the pre-rotation
## config (:v2 from the live test SECRET) still decrypts after Familia is
## reconfigured with the rotated mapping — v1/v2 now registered as the
## "previous" secret's keys and writes moved to a content-addressed tag.
@live_secret               = OT.conf.dig('site', 'secret')
@original_keys             = Familia.config.encryption_keys
@original_version          = Familia.config.current_key_version
receipt, secret            = Onetime::Receipt.spawn_pair 'anon', 3600, 'written before rotation'
rotated_keys, rotated_tag  = CF.build_encryption_keys('brand-new-secret-after-rotation', @live_secret)
Familia.config.encryption_keys     = rotated_keys
Familia.config.current_key_version = rotated_tag
plaintext = Onetime::Secret.load(secret.identifier).decrypted_secret_value
[plaintext, rotated_tag.to_s.start_with?('r')]
#=> ['written before rotation', true]

## CHECKPOINT continued: a NEW envelope written under the rotated config is
## tagged with the content-addressed symbol and round-trips through familia
## (arbitrary version symbols survive envelope serialization).
receipt2, secret2 = Onetime::Receipt.spawn_pair 'anon', 3600, 'written after rotation'
raw_envelope = Familia.dbclient.hget("secret:#{secret2.identifier}:object", 'ciphertext')
tagged = raw_envelope.include?(%("key_version":"#{Familia.config.current_key_version}"))
plaintext = Onetime::Secret.load(secret2.identifier).decrypted_secret_value
Familia.config.encryption_keys     = @original_keys
Familia.config.current_key_version = @original_version
[tagged, plaintext]
#=> [true, 'written after rotation']
