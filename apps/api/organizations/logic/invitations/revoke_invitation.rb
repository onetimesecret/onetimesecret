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
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        @organization = load_organization(@extid)
        verify_organization_admin(@organization)

        # Find invitation by token
        @invitation = Onetime::OrganizationMembership.find_by_token(@token)
        raise_not_found('Invitation not found') if @invitation.nil?

        # Verify invitation belongs to this organization
        if @invitation.organization_objid != @organization.objid
          raise_not_found('Invitation not found')
        end

        # Can only revoke pending invitations
        unless @invitation.pending?
          raise_form_error('Can only revoke pending invitations', field: :token)
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
          user_id: cust.objid,
          organization_id: @organization.extid,
          revoked: true,
        }
      end

      protected

      def verify_organization_admin(organization)
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: 'Only organization owners and admins can revoke invitations',
        )
      end

      def organization_admin?(organization)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, cust.objid
        )
        membership&.admin?
      end
    end
  end
end
