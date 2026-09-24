# lib/onetime/models/session_metadata.rb
#
# frozen_string_literal: true

require 'openssl'

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
  # The raw session_id is a BEARER value — byte-identical to the `onetime.session`
  # cookie and the `session:<sid>` blob key name (see "Keying" above) — so it is
  # deliberately kept OUT of the allow-list (finding F-01): emitting it would hand
  # a privileged operator a replayable session cookie for any user, i.e. silent
  # impersonation past MFA. The colonel view instead identifies a session by
  # #session_handle, a non-reversible keyed digest of the sid that round-trips to
  # revoke but can never be replayed as a credential.
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

    field :session_id       # plain sid; also the identifier and the blob key name.
                            # BEARER value — kept OUT of safe_dump (F-01); the
                            # colonel view exposes #session_handle instead.
    field :org_id           # active ORGANIZATION objid, resolved per write via OrganizationLoader (see TrackMetadata#active_org_id)
    field :user_id          # customer EXTERNAL id (extid, 'ur...'), matching colonel identity everywhere
    field :created_at       # epoch seconds, set once on first observation
    field :last_activity_at # epoch seconds, refreshed every write
    field :ip_address       # copied AS-IS from session_data (already masked upstream by Otto)
    field :user_agent       # copied AS-IS from session_data (already masked upstream by Otto)
    field :auth_method       # primary login method stamped at auth time: 'password' | 'email_auth' | 'webauthn' | 'omniauth' | nil (legacy)
    field :mfa_used          # true | false | nil
    # INTERNAL JOIN KEY — not display data, deliberately absent from the
    # safe_dump allow-list below. Rodauth's active_sessions feature mints its own
    # opaque token (`active_session_id`) and stores only HMAC(that token) in
    # account_active_session_keys; it never sees the Rack sid this record is keyed
    # by. Without this column the Rodauth rows and these records share no value,
    # so the auth UI cannot attach ip/ua/country to a Rodauth session row. The
    # digest — never the raw token, which would be a downgrade in a record that is
    # not encrypted at rest — is computed where a Rodauth instance exists
    # (apps/web/auth/config/features/active_sessions.rb stamps it into the session
    # from update_session) and copied verbatim here by TrackMetadata.
    field :active_session_id_hmac

    # ISO 3166-1 alpha-2 from Otto (env['otto.privacy.geo_country']); nil when
    # unresolved or the privacy layer is absent (see the normalized reader
    # below). Country-only, never a raw IP — resolved by Otto before masking,
    # not derived from ip_address.
    field :geo_country

    # Otto's GeoResolver sentinel for "resolver ran but could not resolve a
    # country" (Otto::Privacy::GeoResolver::UNKNOWN). An internal wire value,
    # never part of this model's contract.
    UNKNOWN_COUNTRY = '**'

    # Normalized geo_country reader — THE single chokepoint that keeps Otto's
    # '**' unknown sentinel out of every emission path (the
    # Onetime::Security::RequestContext#normalize_country precedent: the
    # sentinel is treated like a blank value, never surfaced).
    #
    # Familia reads fields through their PUBLIC getters everywhere it
    # serializes: safe_dump's default field lambda calls `send(:geo_country)`
    # (Horreum defines no `[]`), and to_h / to_h_for_storage do the same. So
    # overriding the getter covers, structurally:
    #   * safe_dump rows (ListForCustomer → colonel per-customer view and the
    #     /auth/active-sessions join map)
    #   * direct reads (Sessions::List#attach_geo_country)
    #   * persistence: to_h_for_storage omits nil fields, so '**' is never
    #     written to storage either (a legacy stored '**' reads back as nil and
    #     is actively removed on the next refresh via remove_stale_nil_fields).
    #
    # Clients can therefore rely on: geo_country is a country code or nil,
    # NEVER '**' and never blank.
    #
    # PREPENDED (not `def geo_country` in the class body) because Familia's
    # method_added guard raises on in-class redefinition of a field-generated
    # method; layering via prepend keeps the generated getter reachable as
    # `super` (the raw stored value).
    GeoCountryNormalization = Module.new do
      def geo_country
        value = super.to_s.strip
        return nil if value.empty? || value == UNKNOWN_COUNTRY

        value
      end
    end
    prepend GeoCountryNormalization

    # Length (hex chars) of the truncated session handle — 128 bits, matching
    # Onetime::Utils::EmailHash's precedent for a truncated keyed digest. Ample
    # collision resistance for identifying one customer's handful of sessions.
    HANDLE_LENGTH = 32

    # Domain-separation label so this digest can never be confused with any other
    # keyed digest of the same sid computed elsewhere in the app.
    HANDLE_DOMAIN = 'session_metadata.handle.v1'

    # Non-reversible, colonel-facing identifier for a session — the value the
    # per-customer session view renders and the revoke endpoint accepts, in place
    # of the raw (bearer) session_id (finding F-01).
    #
    # It is a truncated HMAC-SHA256 of the plain sid, keyed with the application
    # global secret (the same root Onetime::Security::RequestContext and the
    # IncomingConfig recipient hashing key off). Deterministic — the same sid
    # always yields the same handle — so the revoke path can recover the target
    # sid by matching this over the OWNING customer's active_sessions set, yet the
    # sid itself cannot be recovered from the handle and the handle can never be
    # replayed as a session cookie.
    #
    # @param session_id [String, nil]
    # @return [String, nil] 32-char hex handle, or nil for a blank sid.
    def self.handle_for(session_id)
      sid = session_id.to_s
      return nil if sid.empty?

      digest = OpenSSL::Digest.new('sha256')
      OpenSSL::HMAC.hexdigest(digest, OT.global_secret.to_s, "#{HANDLE_DOMAIN}:#{sid}")[0, HANDLE_LENGTH]
    end

    # Instance reader used by the safe_dump allow-list below. A plain derived
    # method (not a stored field), so Familia's default field lambda resolves it
    # via `send(:session_handle)` exactly like any getter — emitting the handle,
    # never the raw sid.
    #
    # @return [String, nil]
    def session_handle
      self.class.handle_for(session_id)
    end

    # POSITIVE allow-list — the security boundary. No token, no payload, no email.
    # session_id (the raw bearer sid) is REPLACED by session_handle, a
    # non-reversible digest (F-01): the colonel view can identify and revoke a
    # session by the handle without ever receiving a replayable cookie value.
    # active_session_id_hmac is omitted on purpose: it is an internal join key,
    # not something the colonel view renders.
    safe_dump_fields(
      :session_handle,
      :user_id,
      :org_id,
      :created_at,
      :last_activity_at,
      :ip_address,
      :user_agent,
      :auth_method,
      :mfa_used,
      :geo_country,
    )
  end
end
