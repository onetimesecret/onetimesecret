# try/unit/models/session_metadata_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the per-session sidecar model (spec docs/specs/colonel-ui/40-*):
#   Onetime::SessionMetadata
#
# Covers:
# - persists + reloads by the PLAIN session id (adaptation #1 — identifier is the
#   bare sid, the same value that is the live `session:<sid>` blob key name)
# - safe_dump returns ONLY the positive allow-list keys (adaptation #6 — the
#   allow-list IS the security boundary)
# - the security proof: no token / email / decrypted-payload / account_id key can
#   surface through safe_dump. The model declares no such field, and Familia's
#   allow-list is positive, so the guarantee is structural — asserted here as an
#   exact key-set equality plus an explicit absence sweep of sensitive names.
# - F-01 regression: the raw bearer sid (== live cookie / Redis blob key) is NEVER
#   in safe_dump; the colonel view gets #session_handle, a non-reversible digest.
#
# Run: try --agent try/unit/models/session_metadata_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/models/session_metadata'

SM = Onetime::SessionMetadata
DB = Familia.dbclient

@nonce = Familia.generate_id[0, 12]
@sid   = "trymeta_#{@nonce}"
@now   = Familia.now.to_i

SM.load(@sid)&.destroy!

# The exact positive allow-list declared on the model. Kept as the source of
# truth for the equality assertion below; sensitive fields are absent BY DESIGN.
# session_handle (a non-reversible digest) stands in for the raw bearer sid,
# which is deliberately NOT exposed (F-01).
ALLOWED = %i[
  session_handle user_id org_id created_at last_activity_at
  ip_address user_agent auth_method mfa_used geo_country
].freeze

# ---- persist + reload -------------------------------------------------

## a new record persists and reloads by the plain sid
@meta = SM.new(session_id: @sid)
@meta.user_id          = "ur_#{@nonce}"
@meta.created_at       = @now
@meta.last_activity_at = @now
@meta.ip_address       = '203.0.113.0'
@meta.user_agent       = 'Chrome on macOS'
@meta.save
@reload = SM.load(@sid)
[@reload.nil?, @reload.session_id, @reload.user_id]
#=> [false, "#{@sid}", "ur_#{@nonce}"]

## the identifier is the plain sid (== the live blob key name, no HMAC)
@reload.identifier
#=> "#{@sid}"

# ---- safe_dump allow-list (the security boundary) ---------------------

## safe_dump emits EXACTLY the positive allow-list, nothing more
@dump = SM.load(@sid).safe_dump
@dump.keys.sort
#=> ALLOWED.sort

## the allow-list carries the metadata we set (ip/ua copied AS-IS, adaptation #3)
[@dump[:user_id], @dump[:ip_address], @dump[:user_agent]]
#=> ["ur_#{@nonce}", "203.0.113.0", "Chrome on macOS"]

## F-01: the raw bearer sid is NOT emitted; the colonel view gets a handle instead
[@dump.key?(:session_id), @dump.key?(:session_handle)]
#=> [false, true]

## the handle is the non-reversible digest of the sid (32 hex chars), not the sid
@handle = SM.load(@sid).safe_dump[:session_handle]
[@handle == SM.handle_for(@sid), @handle == @sid, @handle.length]
#=> [true, false, 32]

## F-01: the raw sid (== live cookie value / `session:<sid>` blob key) appears
## NOWHERE in the serialized payload — no value carries it as a substring either
@dump.values.map(&:to_s).any? { |v| v.include?(@sid) }
#=> false

## SECURITY: no token / email / payload / secret / account_id key can leak
@sensitive = %i[token email payload secret secret_value account_id password
                passphrase session_data raw_ua cookie authorization]
(@dump.keys & @sensitive)
#=> []

## SECURITY: even scanning key NAMES case-insensitively finds no secret carrier
@dump.keys.map(&:to_s).any? { |k| k.match?(/token|email|secret|pass|cookie|payload/i) }
#=> false

# ---- geo_country normalization (the single '**' chokepoint) -----------

## a real country code passes through the reader and safe_dump untouched
@geo = SM.load(@sid)
@geo.geo_country = 'DE'
@geo.save
[@geo.geo_country, SM.load(@sid).geo_country, SM.load(@sid).safe_dump[:geo_country]]
#=> ["DE", "DE", "DE"]

## Otto's '**' unknown sentinel normalizes to nil at the READER — no emission
## path (safe_dump reads via the getter) can ever leak it to a client
@unk = SM.load(@sid)
@unk.geo_country = '**'
[@unk.geo_country, @unk.safe_dump[:geo_country]]
#=> [nil, nil]

## '**' never PERSISTS either: to_h_for_storage reads the getter, nil fields
## are omitted, and the previously stored 'DE' is actively cleared on save
@unk.save
DB.hget(SM.dbkey(@sid), 'geo_country')
#=> nil

## a LEGACY record that stored '**' verbatim (pre-normalization writes) reads
## back as nil through load — the chokepoint covers old data too
DB.hset(SM.dbkey(@sid), 'geo_country', '"**"')
[SM.load(@sid).geo_country, SM.load(@sid).safe_dump[:geo_country]]
#=> [nil, nil]

## blank / whitespace-only values normalize to nil like the sentinel
@blank = SM.new(session_id: "tryblank_#{@nonce}")
@blank.geo_country = '  '
@blank.geo_country
#=> nil

# ---- session_handle: non-reversible identifier (F-01) -----------------

## handle_for is deterministic and non-empty for a real sid
[SM.handle_for(@sid) == SM.handle_for(@sid), SM.handle_for(@sid).to_s.empty?]
#=> [true, false]

## handle_for returns nil for a blank/absent sid — no handle for "no session"
[SM.handle_for(nil), SM.handle_for('')]
#=> [nil, nil]

## distinct sids get distinct handles (so a handle names exactly one session)
SM.handle_for("#{@sid}_a") == SM.handle_for("#{@sid}_b")
#=> false

## the handle is not reversible to (and never equals) the sid it stands for
SM.handle_for(@sid) == @sid
#=> false

# ---- expiration feature present ---------------------------------------

## the model mirrors the session lifetime as its default TTL (30d)
SM.default_expiration
#=> 2_592_000

# Cleanup
SM.load(@sid)&.destroy!
