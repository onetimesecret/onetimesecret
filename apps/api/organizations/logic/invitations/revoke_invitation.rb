# apps/api/organizations/logic/invitations/revoke_invitation.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Invitations
    # Revoke (cancel) a pending invitation
    #
    # DELETE /api/org/:extid/invitations/:token
    #
    # Requires: Owner or Admin role
    #
    class RevokeInvitation < OrganizationAPI::Logic::Base
      attr_reader :organization, :invitation

      def process_params
        @extid = sanitize_identifier(params['extid'])
        @token = sanitize_identifier(params['token'])
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)
        require_entitlement_in!(@organization, 'manage_members')

        # Find invitation by token
        @invitation = Onetime::OrganizationMembership.find_by_token(@token)
        if @invitation.nil?
          raise_not_found(error_key: 'api.organizations.invitations.errors.invitation_not_found')
        end

        # Verify invitation belongs to this organization
        if @invitation.organization_objid != @organization.objid
          raise_not_found(error_key: 'api.organizations.invitations.errors.invitation_not_found')
        end

        # Can only revoke pending invitations
        unless @invitation.pending?
          raise_form_error(error_key: 'api.organizations.invitations.errors.revoke_only_pending', field: :token, error_type: :invalid)
        end
      end

      def process
        OT.ld "[RevokeInvitation] Revoking invitation #{@invitation.objid}"

        email = @invitation.invited_email
        @invitation.revoke!

        OT.info "[RevokeInvitation] Revoked invitation for #{OT::Utils.obscure_email(email)}"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization_id: @organization.extid,
          revoked: true,
        }
      end
    end
  end
end
