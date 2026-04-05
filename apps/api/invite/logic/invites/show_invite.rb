# apps/api/invite/logic/invites/show_invite.rb
#
# frozen_string_literal: true

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
    class ShowInvite < InviteAPI::Logic::Base
      attr_reader :invitation

      def process_params
        @token = sanitize_identifier(params['token'])
      end

      def raise_concerns
        raise_form_error('Token is required', field: :token) if @token.nil? || @token.empty?

        @invitation = load_invitation(@token)

        # Check if organization still exists (may have been deleted)
        unless @invitation.organization
          raise_form_error('Organization no longer exists', field: :token)
        end

        # Check if invitation is still pending
        unless @invitation.pending?
          raise_form_error(
            "Invitation has already been #{@invitation.status}",
            field: :token,
          )
        end

        # Check if invitation has expired
        if @invitation.expired?
          raise_form_error('Invitation has expired', field: :token)
        end
      end

      def process
        OT.ld "[ShowInvite] Showing invitation #{@invitation.objid}"

        success_data
      end

      def success_data
        result = { record: serialize_invitation_public(@invitation) }

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

      def build_auth_methods(sso_config)
        methods = [{ type: 'password', enabled: true }]
        methods << serialize_sso_public(sso_config).merge(type: 'sso') if sso_config&.enabled?
        methods
      end
    end
  end
end
