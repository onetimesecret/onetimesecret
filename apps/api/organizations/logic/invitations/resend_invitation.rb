# apps/api/organizations/logic/invitations/resend_invitation.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Invitations
    # Resend an invitation email
    #
    # POST /api/org/:extid/invitations/:token/resend
    #
    # Requires: Owner or Admin role
    # Generates a new token and resets the expiration timer
    #
    class ResendInvitation < OrganizationAPI::Logic::Base
      MAX_RESENDS = 3

      attr_reader :organization, :invitation

      def process_params
        @extid = sanitize_identifier(params['extid'])
        @token = sanitize_identifier(params['token'])
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)
        verify_organization_admin(
          @organization,
          error_key: 'api.organizations.invitations.errors.admin_required_resend',
        )

        # Find invitation by token
        @invitation = Onetime::OrganizationMembership.find_by_token(@token)
        if @invitation.nil?
          raise_not_found(error_key: 'api.organizations.invitations.errors.invitation_not_found')
        end

        # Verify invitation belongs to this organization
        if @invitation.organization_objid != @organization.objid
          raise_not_found(error_key: 'api.organizations.invitations.errors.invitation_not_found')
        end

        # Can only resend pending invitations
        unless @invitation.pending?
          raise_form_error(error_key: 'api.organizations.invitations.errors.resend_only_pending', field: :token, error_type: :invalid)
        end

        # Rate limit resends
        # rubocop:disable Style/GuardClause -- Guard clause inverts logic incorrectly here
        if @invitation.resend_count.to_i >= MAX_RESENDS
          raise_form_error(
            error_key: 'api.organizations.invitations.errors.resend_limit_reached',
            args: { max: MAX_RESENDS },
            field: :token,
            error_type: :rate_limited,
          )
        end
        # rubocop:enable Style/GuardClause
      end

      def process
        OT.ld "[ResendInvitation] Resending invitation #{@invitation.objid}"

        # Save old token for index update
        old_token = @invitation.token

        # Generate new token and reset timestamp
        @invitation.generate_token!
        @invitation.invited_at   = Familia.now.to_f
        @invitation.resend_count = (@invitation.resend_count.to_i + 1)
        @invitation.save

        # Update token index: remove old, add new (save only adds new)
        @invitation.update_in_class_token_lookup(old_token)

        # Queue invitation email via RabbitMQ
        # Use inviter's locale since they initiated the action
        Onetime::Jobs::Publisher.enqueue_email(
          :organization_invitation,
          {
            invited_email: @invitation.invited_email,
            organization_name: @organization.display_name,
            inviter_email: cust.email,
            role: @invitation.role,
            invite_token: @invitation.token,
            locale: locale || cust.locale || OT.default_locale,
          },
          fallback: :sync,
        )

        OT.info "[ResendInvitation] Resent invitation #{@invitation.objid} (count: #{@invitation.resend_count})"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          record: @invitation.safe_dump,
        }
      end
    end
  end
end
