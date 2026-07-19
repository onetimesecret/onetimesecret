# apps/api/invite/logic/base.rb
#
# frozen_string_literal: true

# Invite API Logic Base Class
#
# Extends v2 logic with modern API patterns for Invite API.
# Handles token-based invitation flows.

require 'onetime/logic/base'

module InviteAPI
  module Logic
    class Base < Onetime::Logic::Base
      # Transform v2 response data to Invite API format
      def success_data
        v2_data  = super
        api_data = v2_data.dup

        # Remove success field (use HTTP status codes)
        api_data.delete(:success)
        api_data.delete('success')

        # Rename custid to user_id (modern naming)
        if api_data.key?(:custid)
          api_data[:user_id] = api_data.delete(:custid)
        elsif api_data.key?('custid')
          api_data['user_id'] = api_data.delete('custid')
        end

        api_data
      end

      protected

      # Load invitation by token with validation
      #
      # @param token [String] the invitation token
      # @return [OrganizationMembership] the invitation
      # @raise [NotFoundError] if token is invalid or expired
      def load_invitation(token)
        invitation = Onetime::OrganizationMembership.find_by_token(token)
        if invitation.nil?
          raise_not_found(error_key: 'api.invite.errors.invitation_not_found_or_expired')
        end
        invitation
      end

      # Serialize invitation for public API response
      # Does NOT include sensitive data like token or internal IDs.
      # The inviter's address is masked (AZ7): this payload is served to any
      # invite-token holder pre-auth, so the raw inviter email must never leak.
      def serialize_invitation_public(invitation)
        organization = invitation.organization
        inviter      = Onetime::Customer.load(invitation.invited_by) if invitation.invited_by

        {
          organization_name: organization&.display_name,
          organization_id: organization&.extid,
          email: invitation.invited_email,
          role: invitation.role,
          invited_by: masked_inviter_email(inviter),
          expires_at: invitation.invitation_expires_at,
          status: effective_invitation_status(invitation),
        }
      end

      # Non-identifying display value for the inviter on the public invite
      # surface: "tom@example.com" -> "t***@e***.com". Returns nil when the
      # inviter record or its email is unavailable.
      def masked_inviter_email(inviter)
        email = inviter&.safe_dump&.dig(:email).to_s
        return nil if email.empty?

        OT::Utils.obscure_email(email)
      end

      # Compute effective status accounting for expiration
      # The stored status may be 'pending' but if past expiry, return 'expired'
      def effective_invitation_status(invitation)
        return 'expired' if invitation.pending? && invitation.expired?

        invitation.status
      end

      # Raise the "already processed" form error with a status-specific,
      # fully-translatable message key. The invitation status ('accepted' /
      # 'active' / 'declined') is a raw backend enum, so it must never be
      # interpolated into a single "already been %{status}" frame — that leaks
      # an untranslated English token and assumes a word order many languages
      # can't honour. Each status maps to its own complete sentence key; any
      # unexpected status falls back to the generic "processed" key.
      def raise_already_processed(invitation)
        opts = { field: :token, error_type: :invalid }
        case invitation.status
        when 'accepted', 'active'
          raise_form_error(
            'This invitation has already been accepted',
            error_key: 'api.invite.errors.invitation_already_accepted',
            **opts,
          )
        when 'declined'
          raise_form_error(
            'This invitation has already been declined',
            error_key: 'api.invite.errors.invitation_already_declined',
            **opts,
          )
        else
          raise_form_error(
            'This invitation has already been processed',
            error_key: 'api.invite.errors.invitation_already_processed',
            **opts,
          )
        end
      end

      # Serialize brand settings for public API response (guest-safe)
      def serialize_brand_public(brand_settings, custom_domain)
        return nil unless brand_settings && custom_domain

        # Familia::HashKey uses [] accessor, not dig
        has_logo = !custom_domain.logo['filename'].to_s.empty?
        has_icon = !custom_domain.icon['filename'].to_s.empty?
        {
          primary_color: brand_settings.primary_color,
          display_name: custom_domain.brand['name'],
          logo_url: has_logo ? "/imagine/#{custom_domain.domainid}/logo.png" : nil,
          icon_url: has_icon ? "/imagine/#{custom_domain.domainid}/icon.png" : nil,
        }
      end

      # Serialize SSO config for public API response (guest-safe)
      def serialize_sso_public(sso_config)
        return nil unless sso_config&.enabled?

        {
          provider_type: sso_config.provider_type,
          display_name: sso_config.display_name,
          enabled: true,
          platform_route_name: sso_config.platform_route_name,
        }
      end
    end
  end
end
