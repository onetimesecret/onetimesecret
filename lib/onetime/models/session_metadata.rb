# lib/onetime/models/session_metadata.rb
#
# frozen_string_literal: true

module Onetime
  # SessionMetadata — a per-session, non-sensitive sidecar record that backs the
  # colonel's PER-CUSTOMER session view (spec docs/specs/colonel-ui/40-*).
  #
  # ## Why this exists
  #
  # The GLOBAL session console (Onetime::Operations::Sessions::List) answers "who
  # is logged in right now?" by SCANning + decrypting every `session:<sid>` blob.
  # That is fine for a site-wide incident sweep but is an anti-pattern for the
  # common question "show me THIS customer's sessions": it decrypts the whole
  # keyspace to find a handful of rows. This model is the index that makes that
  # query O(sessions-for-user): Customer#active_sessions holds the sids, and each
  # sid resolves to one of these lightweight records — no scan, no decrypt.
  #
  # ## Keying: the PLAIN session id (adaptation #1)
  #
  # identifier_field is the plain session id — the exact value that is already the
  # Redis key name of the live blob (`session:<sid>`) and already the cookie
  # value. It is deliberately NOT an HMAC(sid): in this codebase a session dies by
  # deleting the encrypted `session:<sid>` blob (Onetime::Operations::Sessions::
  # Delete + Onetime::Session#delete_session), NOT by removing a Rodauth
  # active_session_keys row — that table only gates Rodauth-mounted routes
  # (mode=full), not the general blob-validated request path. So joining on an
  # HMAC would buy nothing here, and the plain sid introduces NO new exposure: it
  # is already the blob's key name. This record lives under a DISTINCT prefix
  # (`session_metadata:<sid>`) so it can never collide with the live session blob.
  #
  # ## The safe_dump allow-list IS the security boundary (adaptation #6)
  #
  # This record is only ever serialised to the colonel via safe_dump, and the
  # allow-list below is a POSITIVE allow-list: it contains NO token, NO decrypted
  # payload, NO email, NO secret material. That positive list — not any downstream
  # filtering — is the feature's core security guarantee. Adding a field here is a
  # deliberate act of exposing it; do not add anything sensitive.
  #
  # ## Population + lifetime
  #
  # Written best-effort from Onetime::Operations::Sessions::TrackMetadata, called
  # from Onetime::Session#write_session (the one place the plain sid and the
  # post-login session_data hash are both present, refreshed ~per request). TTL
  # mirrors the session lifetime (30d); the sidecar is never authoritative — the
  # live blob is — so a lost or stale record only degrades the convenience index,
  # never auth. Because a blob can be deleted or TTL-expire without touching this
  # record, Customer#active_sessions can outlive its blobs; the per-customer list
  # view reconciles against live keys.
  class SessionMetadata < Familia::Horreum
    # feature :safe_dump (the real Familia feature) with an inline
    # safe_dump_fields(...) block — the Onetime::OrganizationMembership idiom.
    # The brief said `feature :safe_dump_fields`, but that name is NOT a global
    # Familia feature: each model that uses it registers a per-model
    # Model::Features::SafeDumpFields module (via the Autoloader) that itself
    # calls `base.feature :safe_dump`. For a single lean model file the inline
    # form is equivalent and keeps the allow-list visible in one place.
    feature :safe_dump
    feature :expiration

    prefix :session_metadata
    identifier_field :session_id

    # 30 days, mirroring the maximum session lifetime. Refreshed on every write
    # (each authenticated request re-saves the record), so an actively-used
    # session's sidecar never expires out from under it.
    default_expiration 2_592_000

    field :session_id       # plain sid; also the identifier and the blob key name
    field :org_id           # active org id, or nil (see TrackMetadata — no reliable source at write time)
    field :user_id          # customer EXTERNAL id (extid, 'ur...'), matching colonel identity everywhere
    field :created_at       # epoch seconds, set once on first observation
    field :last_activity_at # epoch seconds, refreshed every write
    field :ip_address       # copied AS-IS from session_data (already masked upstream by Otto)
    field :user_agent       # copied AS-IS from session_data (already masked upstream by Otto)
    field :auth_method       # 'omniauth' | 'password' | nil
    field :mfa_used          # true | false | nil

    # POSITIVE allow-list — the security boundary. No token, no payload, no email.
    safe_dump_fields(
      :session_id,
      :user_id,
      :org_id,
      :created_at,
      :last_activity_at,
      :ip_address,
      :user_agent,
      :auth_method,
      :mfa_used,
    )
  end
end
