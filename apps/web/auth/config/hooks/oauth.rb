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

    # verified_by values for which the identity provider asserts
    # email_verified: true. A subset of Onetime::Customer::MAILBOX_VERIFIED_BY;
    # oidc_email_verified? checks both lists. It leaves out 'invite_token':
    # the invitation API also returns the signup token to the inviter
    # (OrganizationMembership safe_dump :token), so an invite signup does not
    # prove that the invitee controls the mailbox.
    OIDC_EMAIL_VERIFIED_BY = %w[email colonel_admin cli_provision].freeze

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
      # HOOK: get_oidc_param  (rodauth-oauth oidc.rb:593, proxied at oidc.rb:630)
      # ========================================================================
      #
      # Line numbers in this block are for the pinned fork, 1.6.6.ots1.
      #
      # Maps a single OIDC standard claim to a value for one `account` row.
      # Called once per claim per scope (oidc.rb:640). Both /userinfo
      # (oidc.rb:159) and the ID token (generate_id_token, oidc.rb:553) fill
      # their claims through fill_with_account_claims, so one answer here
      # reaches both. The gem warns at runtime if any advertised OIDC scope
      # (profile / email / address / phone) is requested without this being
      # defined (oidc.rb:644).
      #
      # Block arity matters: `proxy_get_param` (oidc.rb:661) inspects the
      # method's arity and calls either (account, param) or (account, param, locale).
      # We use a 2-arg signature since we don't localize claims.
      #
      # The OIDC standard claims we handle below come from OIDC_SCOPES_MAP
      # (oidc.rb:8):
      #   email   scope → :email, :email_verified
      #   profile scope → :name, :preferred_username, :updated_at
      #     (plus :family_name, :given_name, :middle_name, :nickname, :profile,
      #      :picture, :website, :gender, :birthdate, :zoneinfo, :locale — we
      #      do not source these; returning nil drops the claim per the proxy's
      #      `unless value.nil?` guard, oidc.rb:668)
      #
      # The `sub` claim is set by the gem from the account_id (oidc.rb jwt_subject)
      # and does not pass through this hook.
      #
      auth.get_oidc_param do |account, param|
        case param.to_sym
        when :email
          account[:email]
        when :email_verified
          # True only when both hold:
          #   1. the Rodauth row is Verified (status_id 2, which the base
          #      feature exposes as account_open_status_value; migration
          #      001_initial.rb seeds account_statuses with these ids), and
          #   2. the linked Customer has mailbox proof
          #      (Customer#mailbox_verified?) and its verified_by is in
          #      OIDC_EMAIL_VERIFIED_BY, which leaves out 'invite_token'
          #      (see the constant).
          #
          # The row status alone is not enough. Every SSO-created account
          # opens Verified (omniauth_verify_account? true) because the
          # upstream IdP vouched for the address, and #4754 holds some of
          # those Customers unverified on purpose. An IdP assertion is not
          # proof that the person controls the mailbox (#4735), so we must
          # not pass it on to our relying parties as email_verified: true.
          #
          # The answer is false, never nil, when proof is missing or cannot
          # be read. OIDC Core 1.0 section 5.1 defines the claim as a
          # boolean: true if the address has been verified, otherwise false.
          # nil would make the gem drop the claim (proxy_get_param,
          # oidc.rb:668), and a missing claim is not a refusal: our own SSO
          # callback reads an absent email_verified as "no hold" and marks
          # the customer verified (hooks/omniauth.rb). features/oauth.rb
          # overrides proxy_get_param so that a `claims` request parameter
          # cannot replace or remove this value either.
          oidc_email_verified?(account)
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
          ts&.respond_to?(:to_i) ? ts.to_i : nil
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

    # Value of the OIDC email_verified claim for a rodauth account row. See
    # the :email_verified branch of get_oidc_param for the rule and why.
    # Fails closed: an unverified row, no linked Customer, a provenance
    # outside OIDC_EMAIL_VERIFIED_BY, or any error resolving one gives false.
    #
    # @param account [Hash] Sequel row from the accounts table
    # @return [Boolean] never nil
    def oidc_email_verified?(account)
      return false unless account[:status_id].to_i == account_open_status_value

      customer = customer_for_account(account)
      return false unless customer&.mailbox_verified? == true

      Hooks::OAuth::OIDC_EMAIL_VERIFIED_BY.include?(customer.verified_by.to_s)
    rescue StandardError => ex
      Onetime.auth_logger&.warn(
        'OAuth email_verified check failed',
        account_id: account[:id],
        error: ex.class.name,
        message: ex.message,
      )
      false
    end
  end
end
