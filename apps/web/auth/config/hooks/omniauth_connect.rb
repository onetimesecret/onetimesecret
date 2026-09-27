# apps/web/auth/config/hooks/omniauth_connect.rb
#
# frozen_string_literal: true

require 'auth/operations/authorize_tenant_connect'
require 'auth/operations/bind_sso_identity'
require 'onetime/session/recent_reauth'
require 'onetime/session/surface'

module Auth::Config::Hooks
  module OmniAuthConnect
    # Tenant Connect enablement constant (#3849, opened by #4427). Kept as a
    # single re-closable kill switch for incident response, not an operator
    # setting: there is no config key on purpose. Closing it refuses every
    # tenant Connect callback with `tenant_connect_prerequisites_incomplete`
    # ahead of the membership gate. The authorization pipeline (surface,
    # membership, ownership) remains mandatory regardless of this value.
    def self.tenant_connect_enabled?
      true
    end

    # The gem checks a cached account, then an existing identity, BEFORE calling
    # account_from_omniauth. Intercept the common callback hook so neither shortcut
    # can switch a Connect to the identity owner's account or skip authorization.
    #
    # VERSION-PINNED INVARIANT (rodauth-omniauth 0.6.2, features/omniauth.rb):
    # before_omniauth_callback_route runs ahead of both shortcuts, and
    # @omniauth_identity is the memo ivar the existing-identity branch reads, so
    # pinning it in bind_omniauth_connect_identity skips the gem's own lookup.
    # RE-VERIFY both on every gem upgrade: a renamed ivar would silently let the
    # gem re-run its lookup, and a reordered hook would let a shortcut run before
    # this wrapper. features/omniauth.rb carries the matching marker for
    # retrieve_omniauth_identity.
    module Callback
      def before_omniauth_callback_route
        consume_omniauth_connect_intent
        session.delete(:validated_omniauth_domain_id)
        super
        if (session_account = resolve_omniauth_connect_account)
          @account = session_account
        end
      end

      private

      def consume_omniauth_connect_intent
        return if defined?(@omniauth_connect_intent_consumed)

        session.delete(:sso_connect_intent)
        @omniauth_connect_raw_intent      = Onetime::SessionSidecar.consume(
          session.id&.public_id, 'sso_connect_intent'
        )
        @omniauth_connect_intent_consumed = true
      end

      def resolve_omniauth_connect_account
        return @omniauth_connect_account if defined?(@omniauth_connect_account)

        # Also covers direct account_from_omniauth callers. Consumption precedes
        # every gate, including malformed payloads and known identity ownership.
        consume_omniauth_connect_intent
        @omniauth_connect_account = nil
        authorized                = authorize_omniauth_connect
        return nil unless authorized

        bind_omniauth_connect_identity(**authorized)
      end

      def omniauth_connect_intent_matches?(intent)
        now = Time.now.utc.to_i
        intent.is_a?(Hash) && intent['surface'].is_a?(Hash) &&
          intent['at'].is_a?(Integer) && intent['at'] <= now &&
          now - intent['at'] <= Onetime::RecentReauth::CONNECT_MAX_AGE &&
          logged_in? && !intent['account_id'].nil? &&
          intent['account_id'].to_s == session_value.to_s
      end

      # No Connect was requested unless a valid intent was consumed, and then
      # this is an ordinary sign-in callback: return nil and let it continue.
      # That branch sits OUTSIDE the fail-closed rescue on purpose (#4431). A
      # failure here says nothing about identity ownership, so it must never
      # surface as identity_connect_conflict.
      def authorize_omniauth_connect
        intent = @omniauth_connect_raw_intent
        unless omniauth_connect_intent_matches?(intent)
          note_omniauth_connect_intent_absent(intent) if logged_in?
          return nil
        end

        authorize_omniauth_connect_lookups(intent)
      end

      # Best-effort diagnostic. A log sink that raises must neither fail an
      # ordinary sign-in nor reclassify it, so the error is reported and
      # dropped here rather than reaching any rescue that refuses.
      def note_omniauth_connect_intent_absent(intent)
        Auth::Logging.log_auth_event(
          :omniauth_connect_intent_absent,
          level: :info,
          provider: omniauth_provider,
          had_intent: !intent.nil?,
        )
      rescue StandardError => ex
        OT.le "[omniauth-connect] intent-absent log failed: #{ex.class}"
      end

      # Every gate that precedes the bind, reached only with a valid intent.
      # When a lookup raises here the authorization is indeterminate and
      # nothing has been written, so refusing is accurate; the rescue stops at
      # this method on purpose (see bind_omniauth_connect_identity).
      # refuse_omniauth_connect! redirects by throw, which the rescue does not
      # intercept.
      def authorize_omniauth_connect_lookups(intent)
        # Shared principal gate: the auth router does not run the Otto strategy's
        # suspension check. Missing Customer data is not evidence of good standing.
        session_account = _account_from_session
        refuse_omniauth_connect!('session_account_missing') unless session_account
        external_id     = session_account[:external_id].to_s
        refuse_omniauth_connect!('session_customer_missing') if external_id.empty?
        customer        = Onetime::Customer.find_by_extid(external_id)
        refuse_omniauth_connect!('session_customer_missing') unless customer
        refuse_omniauth_connect!('session_customer_suspended') if customer.suspended?

        domain_id       = session[:validated_omniauth_domain_id]
        surface         = Onetime::SessionSurface.for_env(request.env)
        surface_bound   = !surface.nil? && intent['surface'] == surface &&
                          Onetime::SessionSurface.matches_request?(session, request.env)
        surface_bound &&= if domain_id
          surface == { 'kind' => 'custom', 'id' => domain_id }
        else
          # An unvalidated callback on a custom host is never platform Connect.
          surface&.fetch('kind', nil) != 'custom'
                          end
        refuse_omniauth_connect!('surface_mismatch', wrong_domain: true) unless surface_bound

        # RecentReauth.satisfied? already consumed the full local proof at
        # initiation. This single-use, age-bounded intent carries that admission
        # across the IdP round trip; consuming a second proof here would deny all
        # legitimate callbacks. SSO itself never records a local proof.
        if domain_id
          # Kill switch before the membership gate, so a closed switch never
          # leaves a tenant_connect_membership_authorized record for a Connect
          # that is refused in the next breath.
          unless Auth::Config::Hooks::OmniAuthConnect.tenant_connect_enabled?
            refuse_omniauth_connect!('tenant_connect_prerequisites_incomplete', wrong_domain: true)
          end
          gate = Auth::Operations::AuthorizeTenantConnect.call(
            account: session_account, domain_id: domain_id,
          )
          refuse_omniauth_connect!('tenant_membership_refused', wrong_domain: true) unless gate.authorized?
        end

        issuer = resolved_issuer
        if Auth::Config::Features::OmniAuth.refuse_issuerless_on_tenant?(
          platform_path: domain_id.nil?, resolved_issuer: issuer,
        )
          refuse_omniauth_connect!('tenant_issuerless', wrong_domain: true)
        end

        { session_account: session_account, issuer: issuer }
      rescue StandardError => ex
        Auth::Logging.log_auth_event(
          :omniauth_connect_lookup_error,
          level: :error,
          error_class: ex.class.name,
        )
        refuse_omniauth_connect!('lookup_error')
      end

      # No rescue here. Once BindSsoIdentity has written the row, an exception
      # from the re-read or the audit log must not be converted into a refusal:
      # the identity IS bound, and telling the user otherwise leaves a credential
      # attached that they believe was rejected. An unhandled error is honest,
      # and a retry is idempotent (BindSsoIdentity accepts an owned tuple).
      #
      # The ownership re-read below is a different case. It refuses only when
      # the row is missing or owned by another account after :ok, which takes a
      # concurrent disconnect or rebind between the write and the read. There
      # the tuple is no longer this account's, so a refusal is the true state,
      # not a masked error.
      def bind_omniauth_connect_identity(session_account:, issuer:)
        # Do NOT call the ordinary identity lookup: its platform-only legacy
        # issuer backfill is a write, and Connect ownership is the exact tuple.
        tuple    = { provider: omniauth_provider.to_s, issuer: issuer.to_s, uid: omniauth_uid }
        outcome  = Auth::Operations::BindSsoIdentity.call(
          db: db, account_id: session_account[account_id_column], **tuple,
        )
        refuse_omniauth_connect!('identity_owned_elsewhere') unless outcome == :ok
        # Cheap guarantee (#4420): the proof was already consumed at initiation;
        # a second bind within max_age needs a fresh ceremony.
        Onetime::RecentReauth.clear(session)
        identity = db[omniauth_identities_table].first(tuple)
        unless identity && identity[omniauth_identities_account_id_column].to_s == session_account[account_id_column].to_s
          refuse_omniauth_connect!('identity_ownership_unconfirmed')
        end

        # Pin both values before returning to the gem's existing-identity branch.
        @omniauth_identity         = identity
        @omniauth_connect_account  = session_account
        Auth::Logging.log_auth_event(
          :omniauth_identity_connected,
          level: :warn,
          provider: omniauth_provider,
          issuer: issuer,
          account_id: session_account[account_id_column],
        )
        # The request phase only stores a validated internal path; re-checking
        # here costs nothing and keeps a tampered sidecar from steering the
        # post-login redirect. Read by the login_redirect override in
        # hooks/omniauth.rb. Never logged.
        @omniauth_connect_redirect = OT::Utils.internal_path_or_nil(@omniauth_connect_raw_intent['redirect'])
        session_account
      end

      # @return [String, nil] the panel path a completed Connect returns to
      def omniauth_connect_redirect
        @omniauth_connect_redirect if defined?(@omniauth_connect_redirect)
      end

      def refuse_omniauth_connect!(reason, wrong_domain: false)
        Auth::Logging.log_auth_event(
          :omniauth_identity_connect_refused,
          level: :warn,
          provider: omniauth_provider,
          reason: reason,
        )
        session.delete(:validated_omniauth_domain_id)
        set_redirect_error_flash 'This identity could not be connected to your account.'
        code = wrong_domain ? 'identity_connect_wrong_domain' : 'identity_connect_conflict'
        redirect "/signin?auth_error=#{code}"
      end
    end
  end
end
