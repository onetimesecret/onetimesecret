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
#
# Run: try --agent try/unit/models/session_metadata_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/models/session_metadata'

SM = Onetime::SessionMetadata

@nonce = Familia.generate_id[0, 12]
@sid   = "trymeta_#{@nonce}"
@now   = Familia.now.to_i

SM.load(@sid)&.destroy!

# The exact positive allow-list declared on the model. Kept as the source of
# truth for the equality assertion below; sensitive fields are absent BY DESIGN.
ALLOWED = %i[
  session_id user_id org_id created_at last_activity_at
  ip_address user_agent auth_method mfa_used
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

## SECURITY: no token / email / payload / secret / account_id key can leak
@sensitive = %i[token email payload secret secret_value account_id password
                passphrase session_data raw_ua cookie authorization]
(@dump.keys & @sensitive)
#=> []

## SECURITY: even scanning key NAMES case-insensitively finds no secret carrier
@dump.keys.map(&:to_s).any? { |k| k.match?(/token|email|secret|pass|cookie|payload/i) }
#=> false

# ---- expiration feature present ---------------------------------------

## the model mirrors the session lifetime as its default TTL (30d)
SM.default_expiration
#=> 2_592_000

# Cleanup
SM.load(@sid)&.destroy!
