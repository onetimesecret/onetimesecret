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
      # Invite API-specific serialization helper
      def json_dump(model)
        return nil if model.nil?

        model.to_h
      end

      alias safe_dump json_dump

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

        {
          organization_name: organization&.display_name,
          organization_description: organization&.description,
          role: invitation.role,
          invited_email: invitation.invited_email,
          invited_at: invitation.invited_at,
          expires_at: invitation.invitation_expires_at,
          expired: invitation.expired?,
          status: invitation.status,
        }
      end
    end
  end
end
