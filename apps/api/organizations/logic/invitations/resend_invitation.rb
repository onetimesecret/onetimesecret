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
        @extid = params['extid']
        @token = params['token']
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

        # Can only resend pending invitations
        unless @invitation.pending?
          raise_form_error('Can only resend pending invitations', field: :token)
        end

        # Rate limit resends
        # rubocop:disable Style/GuardClause -- Guard clause inverts logic incorrectly here
        if @invitation.resend_count.to_i >= MAX_RESENDS
          raise_form_error(
            "Maximum resend limit (#{MAX_RESENDS}) reached",
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
        Onetime::Jobs::Publisher.enqueue_email(
          :organization_invitation,
          {
            invited_email: @invitation.invited_email,
            organization_name: @organization.display_name,
            inviter_email: cust.email,
            role: @invitation.role,
            invite_token: @invitation.token,
          },
          fallback: :sync,
        )

        OT.info "[ResendInvitation] Resent invitation #{@invitation.objid} (count: #{@invitation.resend_count})"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: @invitation.safe_dump,
        }
      end

      protected

      def verify_organization_admin(organization)
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: 'Only organization owners and admins can resend invitations',
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
