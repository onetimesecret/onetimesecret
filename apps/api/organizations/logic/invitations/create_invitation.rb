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
      # Maps an invitee's role to the role-specific plan limit resource.
      # The aggregate `total_members_per_org` cap is enforced separately.
      ROLE_LIMIT_RESOURCES = {
        # Unreachable through this flow today: role validation in raise_concerns
        # rejects `role == 'owner'` because the UI doesn't wire owner invites
        # yet. Kept here so the per-role check works the moment owner invites
        # are enabled — no enforcement gap when the gate is lifted.
        'owner' => 'role_owners_per_org',
        'admin' => 'role_admins_per_org',
        'member' => 'role_members_per_org',
      }.freeze

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
        existing_invite = Onetime::OrganizationMembership.find_pending_by_email(
          @organization, @email
        )
        if existing_invite
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
      #
      # Two checks run in order; whichever fails first raises:
      # 1. Per-role bucket: count of the invited role's active + pending vs.
      #    the role-specific limit (e.g. `role_admins_per_org`).
      # 2. Aggregate cap: total active + pending vs. `total_members_per_org`.
      def check_member_quota!
        # Quota enforcement: fail-open when no billing, fail-closed when enabled.
        # See WithEntitlements module for design rationale.

        # Fail-open conditions: skip quota check
        return unless @organization.respond_to?(:at_limit?)
        return unless @organization.entitlements.any?

        # Per-role bucket check
        role_resource = ROLE_LIMIT_RESOURCES[@role]
        if role_resource
          role_count = @organization.member_count_by_role(@role) +
                       @organization.pending_invitation_count_by_role(@role)
          raise_member_limit_error! if @organization.at_limit?(role_resource, role_count)
        end

        # Aggregate cap check
        total_count = @organization.member_count + @organization.pending_invitation_count
        raise_member_limit_error! if @organization.at_limit?('total_members_per_org', total_count)
      end

      def raise_member_limit_error!
        raise_form_error(
          error_key: 'api.organizations.invitations.errors.member_limit_reached',
          field: 'email',
          error_type: :upgrade_required,
        )
      end
    end
  end
end
