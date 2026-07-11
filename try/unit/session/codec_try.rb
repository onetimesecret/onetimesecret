# try/unit/session/codec_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for Onetime::SessionCodec — the canonical session-blob codec
# extracted from Onetime::Session so the live Rack store (writer) and the
# session admin read verbs (reader) share ONE definition of the at-rest format
# `base64(iv+auth_tag+AES-256-GCM(JSON))--hmac`.
#
# The extraction is behaviour-preserving (try/unit/session_try.rb still round-
# trips write_session/find_session); this file pins the codec's own contract:
# round-trip, tamper rejection, and the never-raise / nil-on-non-blob decode
# that lets Store.load_data fall back safely.
#
# Run: try --agent try/unit/session/codec_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/session/codec'

@secret = 'a-test-session-secret-that-is-long-enough-0123456789'
@codec  = Onetime::SessionCodec.new(@secret)

## encode → decode round-trips a session hash
@hash = { 'account_id' => 7, 'email' => 'alice@example.com', 'authenticated' => true }
@codec.decode(@codec.encode(@hash))
#=> { 'account_id' => 7, 'email' => 'alice@example.com', 'authenticated' => true }

## the encoded blob is the base64(...)--hmac shape (not plaintext JSON)
blob = @codec.encode(@hash)
blob.include?('--') && !blob.start_with?('{')
#=> true

## a wrong secret cannot decode another codec's blob (HMAC rejects it → nil)
other = Onetime::SessionCodec.new('a-different-secret-of-sufficient-length-98765')
other.decode(@codec.encode(@hash))
#=> nil

## a tampered ciphertext body fails to decode (nil, never raises)
blob = @codec.encode(@hash)
data, hmac = blob.split('--', 2)
tampered = "#{data.reverse}--#{hmac}"
@codec.decode(tampered)
#=> nil

## a non-blob (plaintext JSON) is not a valid session blob → nil (caller falls back)
@codec.decode('{"email":"x@y.com"}')
#=> nil

## nil / empty input decodes to nil, never raises
[@codec.decode(nil), @codec.decode('')]
#=> [nil, nil]

## an empty secret is rejected at construction (fail fast, never a silent nil key)
begin
  Onetime::SessionCodec.new('')
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## from_config builds a codec from the running app's session secret
!Onetime::SessionCodec.from_config.nil?
#=> true

## from_config's codec round-trips (same derivation the live store uses)
cc = Onetime::SessionCodec.from_config
cc.decode(cc.encode({ 'email' => 'z@z.com' }))
#=> { 'email' => 'z@z.com' }
