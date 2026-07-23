# try/unit/session/sidecar_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the per-value session sidecar primitive (issue #3858):
#   Onetime::SessionSidecar
#
# The session blob is one encrypted value with one TTL; this primitive stores a
# REGISTERED subset of session fields as sibling STRING keys
# `session:<sid>:<field>` with their own clamped TTLs. Run against real Valkey
# (port 2121 via test_helpers) so SET+EX atomicity, TTL clamping, and GETDEL
# semantics are genuine, not mocked. Covers:
# - key derivation + the closed-registry gate (unregistered -> ArgumentError)
# - the sid format guard (malformed sid -> nil/no-op, no key ever created)
# - encrypted envelope round-trips (true/false/complex values), at-rest format
#   is the canonical SessionCodec blob binding sid + field
# - plaintext envelope round-trips; garbage reads as absent
# - tamper + sid/field binding: unauthentic values read as absent (nil)
# - TTL clamp: a sidecar key never outlives the session blob (remaining blob
#   TTL as ceiling; configured expire_after when no blob exists yet)
# - exists? / delete / purge (one exact DEL of every registry key, no SCAN)
# - consume: atomic read+delete for single-use nonces (#3859) — second consume
#   is nil, binding verified like read
# - middleware hooks: commit externalizes+strips (nil means DEL; merged-stash
#   deletion; fast path returns the same object), merge overlays sidecar-wins
#
# Run: try --agent try/unit/session/sidecar_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'securerandom'
require 'onetime/session/sidecar'

SC = Onetime::SessionSidecar
DB = Familia.dbclient

@codec    = Onetime::SessionCodec.from_config
@sid      = SecureRandom.hex(32) # 64 hex chars, matches SC::SID_FORMAT
@sid2     = SecureRandom.hex(32)
@blob_key = "session:#{@sid}"
@key_mfa  = "session:#{@sid}:awaiting_mfa"
@key_dc   = "session:#{@sid}:domain_context"
@key_fl   = "session:#{@sid}:_flash"

# Clean slate for this run's keys.
DB.del(@blob_key)
SC.purge(@sid)
SC.purge(@sid2)

# ---- key derivation + registry gate -----------------------------------

## key_for derives the sibling key name deterministically — no stored key
## names anywhere, which is what makes purge an exact DEL by name
SC.key_for(@sid, 'awaiting_mfa')
#=> "session:#{@sid}:awaiting_mfa"

## an unregistered field is rejected loudly at write — the registry IS the
## cleanup contract (purge can only delete names it can enumerate)
SC.write(@sid, 'unregistered_field', 'x', codec: @codec)
#=!> ArgumentError

## read / exists? / delete / consume are registry-gated the same way
%i[read exists? delete consume].map do |verb|
  SC.public_send(verb, @sid, 'unregistered_field')
  :no_error
rescue ArgumentError
  :argument_error
end.uniq
#=> [:argument_error]

# ---- sid format guard ---------------------------------------------------

## a malformed sid is a universal no-op (nil/false/0) — the format guard is
## what guarantees every key this module creates matches the Store scan
## exclusion shape, and that a sid can never inject `:`-delimited segments
[SC.write('nothex', 'awaiting_mfa', true, codec: @codec),
 SC.read('nothex', 'awaiting_mfa', codec: @codec),
 SC.consume('nothex', 'awaiting_mfa', codec: @codec),
 SC.exists?('nothex', 'awaiting_mfa'),
 SC.delete('nothex', 'awaiting_mfa'),
 SC.purge('nothex')]
#=> [nil, nil, nil, false, 0, 0]

## ...and no stray key was created for the malformed sid
DB.exists('session:nothex:awaiting_mfa')
#=> 0

# ---- write / read: encrypted envelope -----------------------------------

## write stores the field under its own sibling key and returns the effective
## (clamped) TTL
@ttl = SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
[DB.exists(@key_mfa), @ttl.is_a?(Integer) && @ttl.positive? && @ttl <= 900]
#=> [1, true]

## the key carries its OWN Redis TTL from the atomic SET+EX — never a bare
## SET awaiting a separate EXPIRE, so no crash window can leave an immortal key
DB.ttl(@key_mfa).positive? && DB.ttl(@key_mfa) <= 900
#=> true

## read round-trips the value
SC.read(@sid, 'awaiting_mfa', codec: @codec)
#=> true

## at rest the value is a canonical codec blob (base64(...)--hmac) whose
## envelope binds the sid and field — decodable by the SAME SessionCodec the
## session blob uses (no new crypto)
@envelope = @codec.decode(DB.get(@key_mfa))
[DB.get(@key_mfa).include?('--'), @envelope['sid'] == @sid, @envelope['f'], @envelope['v']]
#=> [true, true, "awaiting_mfa", true]

## false round-trips — a falsy value must survive the envelope, not collapse
## into "absent"
SC.write(@sid, 'awaiting_mfa', false, codec: @codec)
SC.read(@sid, 'awaiting_mfa', codec: @codec)
#=> false

## complex values round-trip type-preserved through the JSON envelope
## (_flash is registered but externalize:false — the explicit API still works,
## per the explicit-use field contract)
SC.write(@sid, '_flash', { 'notice' => ['saved', 'ok'] }, codec: @codec)
SC.read(@sid, '_flash', codec: @codec)
#=> { 'notice' => ['saved', 'ok'] }

# ---- write / read: plaintext envelope -----------------------------------

## a plaintext (encrypted: false) field stores a JSON {'v'=>...} envelope
SC.write(@sid, 'domain_context', 'example.com', codec: @codec)
JSON.parse(DB.get(@key_dc))
#=> { 'v' => 'example.com' }

## ...and reads back the bare value
SC.read(@sid, 'domain_context', codec: @codec)
#=> "example.com"

## garbage in a plaintext key reads as absent, never an error
DB.set(@key_dc, 'not json at all')
SC.read(@sid, 'domain_context', codec: @codec)
#=> nil

# ---- tamper + binding: unauthentic values read as absent ----------------

## flipping a byte of the stored envelope reads as absent (nil) — HMAC is
## verified before any decrypt, same posture as the session blob
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
raw     = DB.get(@key_mfa)
flipped = (raw[0] == 'A' ? 'B' : 'A') + raw[1..]
DB.set(@key_mfa, flipped)
SC.read(@sid, 'awaiting_mfa', codec: @codec)
#=> nil

## sid binding: replaying one session's envelope under ANOTHER sid reads as
## absent — a property the session blob itself does not have
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
DB.set("session:#{@sid2}:awaiting_mfa", DB.get(@key_mfa))
SC.read(@sid2, 'awaiting_mfa', codec: @codec)
#=> nil

## field binding: the same envelope under a DIFFERENT registered field of the
## same sid also reads as absent
DB.set(@key_fl, DB.get(@key_mfa))
SC.read(@sid, '_flash', codec: @codec)
#=> nil

# ---- TTL clamp: a sidecar key never outlives the blob -------------------

## with a live blob at 60s, the 900s default write clamps to the blob's
## REMAINING TTL — a revoked/expiring session's sidecars die no later than
## the blob would have
DB.set(@blob_key, 'x', ex: 60)
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
DB.ttl(@key_mfa).positive? && DB.ttl(@key_mfa) <= 60
#=> true

## an explicit ttl: is clamped the same way
SC.write(@sid, 'domain_context', 'example.com', ttl: 999_999, codec: @codec)
DB.ttl(@key_dc).positive? && DB.ttl(@key_dc) <= 60
#=> true

## with NO blob (mid-first-request, or an explicit pre-commit write), the
## ceiling is the configured expire_after — the TTL the blob is about to get
DB.del(@blob_key)
@ceiling = Onetime.session_config['expire_after'].to_i
SC.write(@sid, 'awaiting_mfa', true, ttl: @ceiling + 999_999, codec: @codec)
#=> @ceiling

# ---- exists? / delete / purge -------------------------------------------

## exists? sees a live key; delete removes exactly it
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
[SC.exists?(@sid, 'awaiting_mfa'), SC.delete(@sid, 'awaiting_mfa'), SC.exists?(@sid, 'awaiting_mfa')]
#=> [true, 1, false]

## purge deletes EVERY registry key for the sid — explicit-use fields
## included — in one exact DEL, no SCAN (the property the entitlement-preview
## keys lack: nothing deletes those on logout)
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
SC.write(@sid, 'domain_context', 'example.com', codec: @codec)
SC.write(@sid, '_flash', 'note', codec: @codec)
[SC.purge(@sid), DB.exists(@key_mfa, @key_dc, @key_fl)]
#=> [3, 0]

# ---- consume: atomic single-use read (#3859 nonces) ---------------------

## consume returns the value AND removes the key in one atomic operation
## (GETDEL) — for single-use nonces where read-then-delete would race
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
[SC.consume(@sid, 'awaiting_mfa', codec: @codec), DB.exists(@key_mfa)]
#=> [true, 0]

## a second consume returns nil — two presenters of the same nonce can never
## both see it
SC.consume(@sid, 'awaiting_mfa', codec: @codec)
#=> nil

## consume verifies the sid binding exactly like read: a replayed value
## consumes to nil, and the planted key is still removed (spent either way)
SC.write(@sid, 'awaiting_mfa', true, codec: @codec)
DB.set("session:#{@sid2}:awaiting_mfa", DB.get(@key_mfa))
[SC.consume(@sid2, 'awaiting_mfa', codec: @codec), DB.exists("session:#{@sid2}:awaiting_mfa")]
#=> [nil, 0]

# ---- middleware hooks: commit / merge -----------------------------------

## commit externalizes registered fields: strips them from the returned hash
## and writes their sidecar keys; the input hash is NOT mutated
@in  = { 'account_id' => 7, 'awaiting_mfa' => true, 'domain_context' => 'example.com' }
@out = SC.commit(@sid, @in, codec: @codec)
[@out, @in.key?('awaiting_mfa'), DB.exists(@key_mfa, @key_dc)]
#=> [{ 'account_id' => 7 }, true, 2]

## merge overlays the externalized values back over the hash — the sidecar
## WINS over a stale blob-resident copy (rolling-deploy back-compat) — and
## reports which fields it merged
@merged = SC.merge(@sid, { 'account_id' => 7, 'awaiting_mfa' => false }, codec: @codec)
[@merged[:data], @merged[:fields].sort]
#=> [{ 'account_id' => 7, 'awaiting_mfa' => true, 'domain_context' => 'example.com' }, ['awaiting_mfa', 'domain_context']]

## commit with the merged stash translates an app-side deletion into a sidecar
## DEL: awaiting_mfa was merged in, then deleted before write-back
SC.commit(@sid, { 'account_id' => 7, 'domain_context' => 'example.com' },
          merged: ['awaiting_mfa', 'domain_context'], codec: @codec)
DB.exists(@key_mfa)
#=> 0

## a present-but-nil field also means DELETE (remove_domain writes nil)
SC.commit(@sid, { 'domain_context' => nil }, codec: @codec)
DB.exists(@key_dc)
#=> 0

## a declared-but-not-externalized field (_flash) stays in the blob hash —
## commit never touches it
SC.commit(@sid, { '_flash' => 'note' }, codec: @codec)
#=> { '_flash' => 'note' }

## the fast path: no registered field present and nothing merged returns the
## SAME hash object with zero Redis commands — the dominant anonymous/CSRF-only
## session pays nothing
@anon = { 'csrf' => 'tok' }
SC.commit(@sid, @anon, codec: @codec).equal?(@anon)
#=> true

# Cleanup
DB.del(@blob_key)
SC.purge(@sid)
SC.purge(@sid2)
