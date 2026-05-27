# apps/api/organizations/logic/invitations/create_invitation.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Invitations
    # Create an invitation to join an organization
    #
    # POST /api/org/:extid/invitations
    #
    # Requires: Owner or Admin role
    # Params:
    #   - email (required): Email address to invite
    #   - role (optional): Role to assign ('member' or 'admin', default: 'member')
    #
    class CreateInvitation < OrganizationAPI::Logic::Base
      attr_reader :organization, :email, :role, :membership

      def process_params
        @extid = sanitize_identifier(params['extid'])
        @email = sanitize_email(params['email'])
        @role  = sanitize_plain_text(params['role'])
        @role  = 'member' if @role.empty?
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)
        require_entitlement_in!(@organization, 'manage_members')

        # Validate email (basic validation before quota check)
        if @email.empty?
          raise_form_error(error_key: 'api.organizations.invitations.errors.email_required', field: 'email', error_type: :missing)
        end
        unless valid_email?(@email)
          raise_form_error(error_key: 'api.organizations.invitations.errors.invalid_email_format', field: 'email', error_type: :invalid)
        end

        # Validate role
        unless %w[member admin].include?(@role)
          raise_form_error(error_key: 'api.organizations.invitations.errors.invalid_role', field: 'role', error_type: :invalid)
        end

        # Owners cannot be invited (must be assigned directly)
        if @role == 'owner'
          raise_form_error(error_key: 'api.organizations.invitations.errors.cannot_invite_as_owner', field: 'role', error_type: :forbidden)
        end

        # Check if user is already a member
        existing_customer = Onetime::Customer.find_by_email(@email)
        if existing_customer && @organization.member?(existing_customer)
          raise_form_error(error_key: 'api.organizations.invitations.errors.user_already_member', field: 'email', error_type: :exists)
        end

        # Check for existing pending invitation
        existing_invite = Onetime::OrganizationMembership.find_by_org_email(
          @organization.objid, @email
        )
        if existing_invite&.pending?
          raise_form_error(error_key: 'api.organizations.invitations.errors.invitation_already_pending', field: 'email', error_type: :exists)
        end

        # Check member quota AFTER basic validation
        # Users should get validation errors before quota/upgrade errors
        check_member_quota!
      end

      def process
        OT.ld "[CreateInvitation] Creating invite for #{OT::Utils.obscure_email(@email)} to org #{@organization.extid}"

        @membership = Onetime::OrganizationMembership.create_invitation!(
          organization: @organization,
          email: @email,
          role: @role,
          inviter: cust,
        )

        # Queue invitation email via RabbitMQ
        # Use inviter's locale since they initiated the action
        Onetime::Jobs::Publisher.enqueue_email(
          :organization_invitation,
          {
            invited_email: @email,
            organization_name: @organization.display_name,
            inviter_email: cust.email,
            role: @role,
            invite_token: @membership.token,
            locale: locale || cust.locale || OT.default_locale,
          },
          fallback: :sync,
        )

        OT.info "[CreateInvitation] Created invitation #{@membership.objid} for #{OT::Utils.obscure_email(@email)}"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          record: @membership.safe_dump,
        }
      end

      def form_fields
        { email: @email, role: @role }
      end

      protected

      # Check member quota against organization's plan limits
      #
      # Uses the organization being invited to for billing context.
      # Only enforced when billing is enabled and plan cache is populated.
      # Counts both active members and pending invitations.
      def check_member_quota!
        # Quota enforcement: fail-open when no billing, fail-closed when enabled.
        # See WithEntitlements module for design rationale.

        # Fail-open conditions: skip quota check
        return unless @organization.respond_to?(:at_limit?)
        return unless @organization.entitlements.any?

        # Fail-closed: billing enabled, enforce quota
        # Count both active members and pending invitations
        current_count = @organization.member_count + @organization.pending_invitation_count

        return unless @organization.at_limit?('members_per_team', current_count)

        raise_form_error(
          error_key: 'api.organizations.invitations.errors.member_limit_reached',
          field: 'email',
          error_type: :upgrade_required,
        )
      end
    end
  end
end
