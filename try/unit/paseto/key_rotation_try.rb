# try/unit/paseto/key_rotation_try.rb
#
# frozen_string_literal: true

#
# Key rotation for the v3 API bearer tokens (#2427).
#
# The current SECRET signs and verifies. SECRET_PREVIOUS can decrypt old
# ciphertext but cannot authenticate bearer tokens. These tryouts walk one rotation:
#
# 1. Before: tokens are signed under SECRET A and verify under A.
# 2. Rotate: SECRET becomes B, SECRET_PREVIOUS lists A. Tokens signed under A
#    stop verifying immediately; new tokens are signed under B.
#
# Pure derivation: no boot and no datastore.

require 'onetime/paseto'

@secret_a = 'decafbad' * 8
@secret_b = 'cafef00d' * 8
@audience = Onetime::Paseto::V3_AUDIENCE
@issuer   = 'rotation.example.test'
@subject  = 'ur0123456789abcdefghijklmno'

def issue_with(keyring)
  Onetime::Paseto::AccessToken.issue(
    subject: @subject, keyring: keyring, audience: @audience, issuer: @issuer, ttl: 3600,
  ).first
end

def verify_with(keyring, token)
  Onetime::Paseto::AccessToken.verify(token, keyring: keyring, audience: @audience, issuer: @issuer)
end

## Step 1: a single SECRET signs and verifies its own tokens
@ring_a  = Onetime::Paseto::Keyring.derive(@secret_a)
@token_a = issue_with(@ring_a)
verify_with(@ring_a, @token_a).kid == @ring_a.signing_key.kid
#=> true

## The keyring accepts exactly one kid before any rotation
@ring_a.kids.size
#=> 1

## Step 2: rotate to SECRET B, keeping A only for ciphertext decryption
@ring_rotated = Onetime::Paseto::Keyring.derive(@secret_b)
@ring_rotated.signing_key.kid == Onetime::Paseto::Keyring.derive(@secret_b).signing_key.kid
#=> true

## The rotated keyring lists only the current kid
@ring_rotated.kids == [@ring_rotated.signing_key.kid]
#=> true

## A token signed before rotation is refused even while A decrypts ciphertext
begin
  verify_with(@ring_rotated, @token_a)
rescue Onetime::Paseto::Error => ex
  ex.class
end
#=> Onetime::Paseto::UnknownKey

## New tokens are signed under SECRET B
@token_b = issue_with(@ring_rotated)
Onetime::Paseto::V4Public.footer_kid(Onetime::Paseto::V4Public.parse(@token_b).footer) == @ring_rotated.signing_key.kid
#=> true

## Tokens signed under SECRET B keep working
verify_with(@ring_rotated, @token_b).subject == @subject
#=> true

## Rotation does not change the claims carried by a newly issued token
[verify_with(@ring_rotated, @token_b).subject, verify_with(@ring_rotated, @token_b).scope]
#=> ['ur0123456789abcdefghijklmno', ['*']]

## A deployment whose SECRET was never A or B holds no usable key for either token
@ring_stranger = Onetime::Paseto::Keyring.derive('deadbeef' * 8)
[@token_a, @token_b].map do |token|
  verify_with(@ring_stranger, token)
  :accepted
rescue Onetime::Paseto::UnknownKey
  :unknown_key
end
#=> [:unknown_key, :unknown_key]

## Nothing in a keyring's printable form is key material
@ring_rotated.inspect.include?(@ring_rotated.signing_key.private_key.raw_private_key.unpack1('H*'))
#=> false
