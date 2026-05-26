# apps/web/auth/config/hooks/oauth.rb
#
# frozen_string_literal: true

#
# OAuth2/OIDC Identity Provider lifecycle hooks.
#
# Companion to apps/web/auth/config/features/oauth.rb. The feature module
# enables :oauth_authorization_code_grant, :oauth_pkce, :oidc, and
# :oauth_token_revocation; this module wires user-facing claim mapping
# so the gem can serve /userinfo responses and embed ID-token claims.
#
# Gem hook reference (rodauth-oauth 1.6.4):
#   lib/rodauth/features/oidc.rb
#     - auth_methods :get_oidc_param (line 110)
#     - auth_methods :get_additional_param (line 111)
#     - auth_methods :fill_with_account_claims (line 109)
#     - auth_methods :get_oidc_account_last_login_at (line 107)
#
# The `account` argument is the Sequel row Hash returned by `account_ds(sub).first`
# (oidc.rb:130), so `account[:email]` and `account[:status_id]` are the canonical
# accessors — not `account.public_send(:email)` as the gem's docstring example
# suggests.
#
# Issue: https://github.com/onetimesecret/onetimesecret/issues/3104
#

module Auth::Config::Hooks
  module OAuth
    # Endpoint paths the rodauth-oauth gem mounts (or that we mount in
    # router.rb for discovery). All are relative to the auth app's
    # uri_prefix (`/auth`). The JSON-mode exemption below uses this list
    # to bypass `only_json? true` in base.rb on requests that the OAuth
    # spec defines as form-encoded or browser-driven.
    #
    # See: apps/web/auth/router.rb (discovery routes)
    # See: rodauth-oauth-1.6.4/lib/rodauth/features/*.rb (auto-mounted)
    OAUTH_EXEMPT_PATHS = %w[
      /.well-known/openid-configuration
      /.well-known/oauth-authorization-server
      /jwks
      /authorize
      /token
      /userinfo
      /revoke
    ].freeze

    def self.configure(auth)
      # ========================================================================
      # JSON Mode Override for OAuth/OIDC Endpoints — now centralized
      # ========================================================================
      #
      # OAUTH_EXEMPT_PATHS above is the source of truth for the exempt set.
      # The actual `only_json?` setter is owned by Auth::Config::JsonMode
      # (apps/web/auth/config/json_mode.rb) because rodauth's
      # def_auth_value_method REPLACES rather than chains. If we kept a
      # per-hook block here, it would silently clobber the OmniAuth block
      # whenever both AUTH_SSO_ENABLED and AUTH_OAUTH_ENABLED were true.
      #
      # Endpoints in OAUTH_EXEMPT_PATHS that need to skip JSON-only mode:
      #   - /authorize     — browser-driven (302 redirects, HTML forms)
      #   - /token         — application/x-www-form-urlencoded body
      #   - /revoke        — application/x-www-form-urlencoded body
      #   - /.well-known/* — polled by browsers/SDKs without JSON Content-Type
      #   - /jwks          — clients GET without a JSON Content-Type
      #   - /userinfo      — Bearer-only GET/POST; clients omit JSON CT

      # ========================================================================
      # HOOK: get_oidc_param  (rodauth-oauth oidc.rb:583, proxied at oidc.rb:620)
      # ========================================================================
      #
      # Maps a single OIDC standard claim to a value for one `account` row.
      # Called once per claim per scope. The gem warns at runtime if any
      # advertised OIDC scope (profile / email / address / phone) is requested
      # without this being defined — see oidc.rb:634.
      #
      # Block arity matters: `proxy_get_param` (oidc.rb:651) inspects the
      # method's arity and calls either (account, param) or (account, param, locale).
      # We use a 2-arg signature since we don't localize claims.
      #
      # The OIDC standard claims we handle below come from OIDC_SCOPES_MAP
      # (oidc.rb:9):
      #   email   scope → :email, :email_verified
      #   profile scope → :name, :preferred_username, :updated_at
      #     (plus :family_name, :given_name, :middle_name, :nickname, :profile,
      #      :picture, :website, :gender, :birthdate, :zoneinfo, :locale — we
      #      do not source these; returning nil drops the claim per the proxy's
      #      `unless value.nil?` guard, oidc.rb:660)
      #
      # The `sub` claim is set by the gem from the account_id (oidc.rb jwt_subject)
      # and does not pass through this hook.
      #
      auth.get_oidc_param do |account, param|
        case param.to_sym
        when :email
          account[:email]
        when :email_verified
          # An OTS account is considered verified once its status flips from
          # "Unverified" (status_id=1) to "Verified" (status_id=2). The rodauth
          # base feature exposes these as account_open_status_value (2) and
          # account_unverified_status_value (1) — see migration 001_initial.rb
          # which seeds the account_statuses table with the same ids.
          account[:status_id].to_i == account_open_status_value
        when :name, :preferred_username
          # OTS Customer is the user-facing profile record (Familia/Redis).
          # The account row's external_id links to Customer via
          # Customer.find_by_extid; fall back to email lookup if external_id
          # hasn't been backfilled (mirrors hooks/login.rb:256).
          customer = customer_for_account(account)
          customer&.custid || account[:email]
        when :updated_at
          # Spec: NumericDate (seconds since epoch). Use the account's
          # updated_at column written by migration 001_initial.rb (line 38).
          ts = account[:updated_at]
          ts.respond_to?(:to_i) ? ts.to_i : nil
          # Unsupported claims: case returns nil and the proxy filters nils.
        end
      end

      # ========================================================================
      # `get_oidc_account_last_login_at` — intentionally NOT overridden.
      # ========================================================================
      #
      # The gem's default (oidc.rb:352) reads from active_sessions_table when
      # :active_sessions is enabled, which is true for OTS (the :oidc feature
      # `depends :active_sessions` per the exploration notes). The
      # `accounts` table itself has no last_login_at column; the
      # `account_activity_times` table is only populated when the
      # :account_expiration feature is enabled, which it isn't.
      #
      # If we ever start advertising the `auth_time` claim under stricter SLAs,
      # consider deriving from Customer#last_login instead.

      # ========================================================================
      # `id_token_claims` — intentionally NOT overridden.
      # ========================================================================
      #
      # The default (oidc.rb:559) populates sub, aud, iat, exp, iss, nonce, acr,
      # auth_time, at_hash, and c_hash. fill_with_account_claims is then called
      # separately for ID-token claim merging when scopes include profile/email.
      # We don't add custom top-level claims in v1.

      # ========================================================================
      # `before_authorize` — intentionally NOT wired here.
      # ========================================================================
      #
      # This hook (oauth_authorize_base.rb:53) is the right extension point for
      # future per-tenant authorization gating (e.g. issue #28 SSO domain
      # restriction parity). Skipped for v1 because rodauth doesn't register a
      # DSL setter for it (no auth_methods entry — see oauth_authorize_base.rb:31),
      # so wiring it requires a `def before_authorize` override at class scope
      # rather than a `auth.before_authorize do` block. Leave as a follow-up.
    end
  end
end

# ============================================================================
# Helper methods injected into the Rodauth instance.
# ============================================================================
#
# Defined here rather than inline in the `configure` block because Rodauth's
# DSL only exposes helpers declared via auth_methods. The cleanest way to add
# instance helpers usable from inside auth_*-style blocks is to reopen
# Auth::Config and add private methods.
#
module Auth # rubocop:disable Style/OneClassPerFile
  class Config < Rodauth::Auth
    private

    # Resolve the Onetime::Customer record for a rodauth account row.
    # Prefers external_id (matches hooks/login.rb:71 and hooks/account.rb:244
    # convention); falls back to email for accounts created before extid
    # backfill (matches hooks/login.rb:256).
    #
    # @param account [Hash] Sequel row from the accounts table
    # @return [Onetime::Customer, nil]
    def customer_for_account(account)
      return nil unless account

      extid      = account[:external_id]
      customer   = Onetime::Customer.find_by_extid(extid) if extid && !extid.to_s.empty?
      customer ||= Onetime::Customer.find_by_email(account[:email]) if account[:email]
      customer
    rescue StandardError => ex
      Onetime.auth_logger&.warn(
        'OAuth customer lookup failed',
        account_id: account[:id],
        error: ex.class.name,
        message: ex.message,
      )
      nil
    end
  end
end
