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
        {
          record: serialize_invitation_public(@invitation),
        }
      end
    end
  end
end
