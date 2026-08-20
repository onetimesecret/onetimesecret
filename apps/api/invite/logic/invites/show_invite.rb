# apps/api/invite/logic/invites/show_invite.rb
#
# frozen_string_literal: true

require 'auth/restrict_to'
require 'onetime/security/invite_token_rate_limiter'

module InviteAPI::Logic
  module Invites
    # Show invitation details
    #
    # GET /api/invite/:token
    #
    # Auth: noauth (token validates access)
    # Returns invitation details without sensitive data.
    # Used to display invitation info before accept/decline.
    #
    # Returns structured responses for ALL invitation states:
    # - pending: actionable invitation
    # - accepted/active: already joined
    # - declined: user declined
    # - expired: past TTL
    # - revoked: admin cancelled (404 - record deleted)
    #
    # Only raises 404 for truly invalid tokens (not found).
    #
    class ShowInvite < InviteAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :invitation

      def process_params
        @token = sanitize_identifier(params['token'])
      end

      def raise_concerns
        # Rate limiting for noauth endpoint - prevents token enumeration
        client_ip    = @strategy_result&.metadata&.dig(:ip) || @strategy_result&.metadata&.dig('ip') || '0.0.0.0'
        rate_limiter = Onetime::Security::InviteTokenRateLimiter.new(client_ip)
        rate_limiter.check!
        rate_limiter.record_attempt

        if @token.nil? || @token.empty?
          raise_form_error(error_key: 'api.invite.errors.token_required', field: :token, error_type: :missing)
        end

        @invitation = load_invitation(@token)

        # Check if organization still exists (may have been deleted)
        unless @invitation.organization
          raise_form_error(error_key: 'api.invite.errors.organization_no_longer_exists', field: :token, error_type: :missing)
        end

        # NOTE: We no longer raise errors for non-pending or expired invitations.
        # The frontend needs the structured response to show appropriate UI.
      end

      def process
        auth_logger.debug 'Showing invitation',
          invitation_id: @invitation.objid,
          status: @invitation.status

        success_data
      end

      def success_data
        result = { record: serialize_invitation_public(@invitation) }

        # Add computed status flag for frontend branching.
        # NOTE: This response must NOT vary on whether the invited email
        # already has an account (AZ7 account-existence oracle) -- the
        # endpoint is noauth and gated only by the invite token.
        result[:record][:actionable] = actionable?

        auth_logger.debug 'Building success_data',
          domain_strategy: domain_strategy,
          display_domain: display_domain,
          custom_domain: custom_domain?

        # ADR-034#invite-signup-is-gated (#4139): what this HOST permits, on
        # every host.
        #
        # POST /:token/signup is gated on Auth::RestrictTo.allows?(env,
        # 'password') and 404s where password is restricted away. Without this
        # field the invite page renders a password signup form whose submit
        # then 404s, with nothing in the response to predict it.
        #
        # UNCONDITIONAL, deliberately NOT inside the custom_domain? branch
        # below: this ADR's stated live case is an SSO-only INSTALL, where the
        # restriction is global and the request host is canonical. Gating this
        # on custom_domain? would leave exactly that case blind — the
        # regression that motivated the field.
        resolution = restrict_to_resolution

        # #to_wire is the resolution's own serialization, shared verbatim with
        # the settings API's details.effective_restrict_to
        # (ADR-034#settings-api-serializes-effective-restrict-to), so one
        # client-side type describes both surfaces.
        result[:record][:effective_restrict_to] = resolution.to_wire

        if custom_domain?
          domain = Onetime::CustomDomain.from_display_domain(display_domain)
          auth_logger.debug 'Found custom domain',
            domain: domain&.display_domain
          if domain
            result[:record][:branding]     = serialize_brand_public(domain.brand_settings, domain)
            result[:record][:auth_methods] = build_auth_methods(domain, resolution)
          end
        end
        result
      end

      private

      # Whether this invitation can still be acted upon (accept/decline)
      def actionable?
        @invitation.pending? && !@invitation.expired?
      end

      # Resolver output for the request host (ADR-034#resolution-is-model-owned
      # — resolution is model-owned and re-derived NOWHERE).
      #
      # Auth::RestrictTo.resolution_for owns input gathering (the
      # custom-domain 'sso' pin, the runtime-availability half of
      # ADR-034#degradation-is-fail-closed) and
      # SigninConfig.resolve_restrict_to owns the rule, so this display
      # surface answers with the same verdict the POST /:token/signup gate
      # enforces. Calling the entry point rather than the resolver directly
      # also keeps this insulated from the resolver's argument list.
      #
      # @return [Onetime::CustomDomain::SigninConfig::RestrictToResolution]
      def restrict_to_resolution
        Auth::RestrictTo.resolution_for(restrict_to_env)
      end

      # Sign-in methods this host will actually accept.
      #
      # Every entry is filtered through the resolution
      # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference): a
      # page that advertises a method the host rejects is the display/runtime
      # disagreement ADR-024 exists to kill. The list can legitimately come
      # back EMPTY (an :unavailable resolution allows nothing,
      # ADR-034#degradation-is-fail-closed) — the
      # frontend must render that as "sign-in unavailable", never as a reason
      # to fall back to standard mode.
      #
      # NOTE the naming seam: the wire type is 'magic_link' while the
      # restrict_to value for the same method is 'email_auth'
      # (SigninConfig::RESTRICT_TO_VALUES). Ask the resolution about
      # 'email_auth'.
      def build_auth_methods(domain, resolution)
        methods = []
        methods << { type: 'password', enabled: true } if resolution.allows?('password')
        methods << { type: 'magic_link', enabled: true } if email_auth_enabled? && resolution.allows?('email_auth')
        methods.concat(build_sso_auth_methods(domain)) if resolution.allows?('sso')
        methods
      end

      # Use the same runtime availability ladder as the sign-in route. A stored
      # enabled flag alone can advertise tenant SSO after AUTH_ENABLED, provider
      # support, or SigninConfig has made that route unusable.
      def build_sso_auth_methods(domain)
        domain_id  = domain.identifier
        sso_config = domain.sso_config

        if Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(
          domain_id,
          sso_config: sso_config,
        )
          return [serialize_sso_public(sso_config).merge(type: 'sso')]
        end

        return [] unless Onetime::CustomDomain::SsoConfig.sso_available_for_tenant_host?(domain_id)

        # PLATFORM FALLBACK. These entries deliberately carry NO :provider_type,
        # unlike the tenant arm above (serialize_sso_public reads
        # sso_config.provider_type). AuthConfig#sso_providers yields only
        # 'route_name' and 'display_name', and the platform registry's own
        # identity (SsoProvider::Registry keys: oidc, entra, google, github) is
        # a different vocabulary from tenant PROVIDER_TYPES (oidc, entra_id) —
        # 'entra' vs 'entra_id' collide, and google/github have no tenant
        # counterpart at all. Emitting a registry key as :provider_type would
        # put a third vocabulary on a field whose values consumers read as the
        # tenant enum, so the field stays absent. What identifies a
        # platform-fallback provider is :platform_route_name, which the tenant
        # arm carries too — that is the field to route and branch on.
        Onetime.auth_config.sso_providers.filter_map do |provider|
          route_name = provider['route_name'].to_s
          next if route_name.empty?

          {
            type: 'sso',
            enabled: true,
            platform_route_name: route_name,
            display_name: provider['display_name'].to_s,
          }
        end
      end

      def email_auth_enabled?
        Onetime.auth_config.email_auth_enabled?
      end
    end
  end
end
