# apps/api/invite/logic/invites/decline_invite.rb
#
# frozen_string_literal: true

require 'onetime/security/invite_token_rate_limiter'

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

        OT.info '[DeclineInvite] Invitation declined',
          event: 'invite.declined',
          invitation_id: @invitation.objid,
          organization_id: organization&.extid,
          invited_email: OT::Utils.obscure_email(@invitation.invited_email),
          result: :success

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
