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
        raise_not_found('Invitation not found or expired') if invitation.nil?
        invitation
      end

      # Serialize invitation for public API response
      # Does NOT include sensitive data like token or internal IDs
      def serialize_invitation_public(invitation)
        organization = invitation.organization
        inviter      = Onetime::Customer.load(invitation.invited_by) if invitation.invited_by

        {
          organization_name: organization&.display_name,
          organization_id: organization&.extid,
          email: invitation.invited_email,
          role: invitation.role,
          invited_by_email: inviter&.safe_dump&.dig(:email),
          expires_at: invitation.invitation_expires_at,
          status: invitation.status,
        }
      end

      # Serialize brand settings for public API response (guest-safe)
      def serialize_brand_public(brand_settings, custom_domain)
        return nil unless brand_settings && custom_domain

        has_logo = !custom_domain.logo&.dig('filename').to_s.empty?
        has_icon = !custom_domain.icon&.dig('filename').to_s.empty?
        {
          primary_color: brand_settings.primary_color,
          display_name: custom_domain.brand&.dig('name'),
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
