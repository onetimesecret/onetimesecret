# apps/api/invite/logic/invites/show_invite.rb
#
# frozen_string_literal: true

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

        raise_form_error('Token is required', field: :token) if @token.nil? || @token.empty?

        @invitation = load_invitation(@token)

        # Check if organization still exists (may have been deleted)
        unless @invitation.organization
          raise_form_error('Organization no longer exists', field: :token)
        end

        # NOTE: We no longer raise errors for non-pending or expired invitations.
        # The frontend needs the structured response to show appropriate UI.
      end

      def process
        OT.ld "[ShowInvite] Showing invitation #{@invitation.objid} (status: #{@invitation.status})"

        success_data
      end

      def success_data
        result = { record: serialize_invitation_public(@invitation) }

        # Add computed status flags for frontend branching
        result[:record][:actionable]     = actionable?
        result[:record][:account_exists] = account_exists?

        OT.ld "[ShowInvite.success_data] domain_strategy=#{domain_strategy.inspect} display_domain=#{display_domain.inspect}"
        OT.ld "[ShowInvite.success_data] custom_domain?=#{custom_domain?}"

        if custom_domain?
          domain = Onetime::CustomDomain.from_display_domain(display_domain)
          OT.ld "[ShowInvite.success_data] found domain=#{domain&.display_domain.inspect}"
          if domain
            result[:record][:branding]     = serialize_brand_public(domain.brand_settings, domain)
            result[:record][:auth_methods] = build_auth_methods(domain.sso_config)
          end
        end
        result
      end

      private

      # Whether this invitation can still be acted upon (accept/decline)
      def actionable?
        @invitation.pending? && !@invitation.expired?
      end

      # Whether an account exists for the invited email
      def account_exists?
        Onetime::Customer.email_exists?(@invitation.invited_email)
      end

      def build_auth_methods(sso_config)
        methods = [{ type: 'password', enabled: true }]
        methods << { type: 'magic_link', enabled: true } if email_auth_enabled?
        methods << serialize_sso_public(sso_config).merge(type: 'sso') if sso_config&.enabled?
        methods
      end

      def email_auth_enabled?
        Onetime.auth_config.email_auth_enabled?
      end
    end
  end
end
