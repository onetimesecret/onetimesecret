# apps/api/invite/logic/invites/decline_invite.rb
#
# frozen_string_literal: true

module InviteAPI::Logic
  module Invites
    # Decline an invitation to join an organization
    #
    # POST /api/invite/:token/decline
    #
    # Auth: noauth (token validates access)
    # No authentication required - the invitee may not have an account.
    # The token itself serves as proof of access.
    #
    class DeclineInvite < InviteAPI::Logic::Base
      attr_reader :invitation

      def process_params
        @token = params['token']
      end

      def raise_concerns
        raise_form_error('Token is required', field: :token) if @token.nil? || @token.empty?

        @invitation = load_invitation(@token)

        # Check if organization still exists (may have been deleted)
        unless @invitation.organization
          raise_form_error('Organization no longer exists', field: :token)
        end

        # Check if invitation is still pending
        return if @invitation.pending?

        raise_form_error(
          "Invitation has already been #{@invitation.status}",
          field: :token,
        )

        # NOTE: We allow declining expired invitations since the user
        # is explicitly rejecting it. No harm in processing the decline.
      end

      def process
        OT.ld "[DeclineInvite] Declining invitation #{@invitation.objid}"

        organization = @invitation.organization
        @invitation.decline!

        OT.info "[DeclineInvite] Invitation for #{OT::Utils.obscure_email(@invitation.invited_email)} to #{organization&.extid} declined"

        success_data
      end

      def success_data
        {
          declined: true,
          organization_name: @invitation.organization&.display_name,
        }
      end
    end
  end
end
