# apps/web/auth/operations/reauth_offer.rb
#
# frozen_string_literal: true

require 'onetime/session/reauth_policy'
require 'onetime/session/surface'

require_relative 'read_webauthn_credentials'
require_relative '../signin_enabled'

module Auth
  module Operations
    # Assemble the four inputs {Onetime::ReauthPolicy.eligible_methods}
    # needs and return the offer for THIS account on THIS request's
    # surface (#4414, epic #4408).
    #
    # The offer is the single source of truth every re-auth surface will
    # consult: the future GET /auth/reauth-offer endpoint that renders
    # the UI, the POST /auth/reauth endpoint that gates which methods
    # it may accept, and any diagnostic surface that needs to explain
    # why the user is stuck. All three read exactly what {call} returns —
    # no separate derivations.
    #
    # ## Wire shape
    #
    #     {
    #       surface:               { kind: :canonical } | { kind: :subdomain, host: … } |
    #                              { kind: :custom, id: … } | nil,
    #       methods:               ['webauthn', 'password'] (ordered subset),
    #       webauthn_credentials:  the ReadWebauthnCredentials projection
    #                              (safe to render — no verification material),
    #       related_origins:       the resolved related-origin surface descriptors
    #                              (empty on canonical or on a tenant with no declared set)
    #     }
    #
    # ## What the caller must NOT do
    #
    # - Do NOT re-derive `methods` from the other keys; the policy is
    #   the ONLY place that decides which paths may be offered, and a
    #   caller that intersects the credentials against the surface on
    #   its own reproduces the very drift {Onetime::ReauthPolicy} exists
    #   to eliminate.
    # - Do NOT pass `webauthn_credentials` back to a client whose account
    #   the caller has not verified. The projection carries only
    #   `{scope:}` / `{scope:, id:}` — no keys, no counters — but it is
    #   still per-account state.
    #
    # ## Fail-closed
    #
    # A missing account_id, an unresolved surface, or any raise from the
    # credential/config reads yields an empty offer with
    # `methods: []` — the caller must refuse re-authentication, not
    # silently widen. The surface descriptor is still reported when
    # available so a caller can render a "wrong host" notice.
    class ReauthOffer
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param account_id [Integer, nil]
      # @param env [Hash] Rack env for the current request
      # @return [Hash] the frozen offer payload
      def call(account_id:, env:)
        surface     = Onetime::SessionSurface.for_env(env)
        credentials = safe_read_credentials(account_id)
        related     = safe_related_origins(env)
        # A nil account_id has no owner to re-authenticate, so no method
        # may be offered — not even password, which would otherwise fire
        # from the install-level capability alone. The offer's callers
        # (a Connect intent, an identity bind) treat methods=[] as
        # "refuse the flow", which is the right answer for an offer
        # whose account is unknown.
        password    = !account_id.nil? && safe_password_enabled?(account_id, env)

        methods = Onetime::ReauthPolicy.eligible_methods(
          surface,
          password_enabled: password,
          webauthn_credentials: credentials,
          related_origins: related,
        )

        {
          surface: surface,
          methods: methods,
          webauthn_credentials: credentials.freeze,
          related_origins: related,
        }.freeze
      end

      private

      def safe_read_credentials(account_id)
        return [] if account_id.nil?

        ReadWebauthnCredentials.new(@db).call(account_id)
      rescue StandardError => ex
        log_failure('read_webauthn_credentials', ex, account_id: account_id)
        []
      end

      # Whether password sign-in is available for this request per the
      # runtime gate {Auth::SigninEnabled}. That already intersects the
      # install-level capability (AUTH_ENABLED / AUTH_SIGNIN) with the
      # per-tenant SigninConfig, so this returns the SAME value the
      # rest of the auth stack applies to POST /auth/login.
      def safe_password_enabled?(account_id, env)
        return false unless Auth::SigninEnabled.enabled_for_request?(env)

        password_challengeable?(account_id)
      rescue Onetime::SigninPolicyUnavailable
        # An unreadable per-domain policy on a non-operator host reads
        # as "we do not know" — the offer cannot claim password works.
        false
      rescue StandardError => ex
        log_failure('signin_enabled', ex)
        false
      end

      def password_challengeable?(account_id)
        account = @db[:accounts]
          .where(id: Integer(account_id))
          .select(:email)
          .first
        return false unless account
        return true if @db[:account_password_hashes].where(id: Integer(account_id)).any?

        customer = Onetime::Customer.find_by_email(account[:email])
        customer&.has_passphrase? == true
      rescue StandardError => ex
        log_failure('password_challengeable', ex, account_id: account_id)
        false
      end

      # Resolve the tenant's declared related-origins surface descriptors,
      # or []. Only :custom surfaces can have a per-domain declaration;
      # canonical requests skip the lookup.
      def safe_related_origins(env)
        return [] unless env['onetime.domain_strategy'].to_s == 'custom'

        domain_id = env['onetime.custom_domain_id']
        return [] if domain_id.to_s.empty?

        config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)
        return [] unless config

        config.related_origin_surfaces
      rescue StandardError => ex
        log_failure('related_origins', ex, domain_id: env['onetime.custom_domain_id'])
        []
      end

      def log_failure(step, exception, **context)
        Onetime.get_logger('Auth::ReauthOffer').warn "Reauth offer step failed: #{step}",
          error: exception.message,
          error_class: exception.class.name,
          **context
      end
    end
  end
end
