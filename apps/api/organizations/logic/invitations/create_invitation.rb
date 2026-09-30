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
      # The aggregate `total_members_per_org` count is checked separately.
      ROLE_LIMIT_RESOURCES = {
        # Unreachable through this flow today: role validation in raise_concerns
        # rejects `role == 'owner'` because the UI doesn't wire owner invites
        # yet.
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

        # Domain-scoped members cannot perform member operations
        actor_membership = Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, cust.objid)
        if actor_membership&.domain_scoped?
          raise_form_error(error_key: 'api.organizations.errors.domain_scoped_forbidden', error_type: :forbidden)
        end

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

        # Log-only: records member counts against the plan values.
        note_member_counts
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
        # Use inviter's locale since they initiated the action.
        # Blank ("") locales are truthy and slip past a bare `||`; treat as missing.
        email_locale = locale
        email_locale = cust.locale if email_locale.to_s.strip.empty?
        email_locale = OT.default_locale if email_locale.to_s.strip.empty?
        Onetime::Jobs::Publisher.enqueue_email(
          :organization_invitation,
          {
            invited_email: @email,
            organization_name: @organization.display_name,
            inviter_email: cust.email,
            role: @role,
            invite_token: @membership.token,
            locale: email_locale,
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

      # Compare member counts against the organization's plan values
      #
      # Uses the organization being invited to for billing context.
      # Only evaluated when billing is enabled and plan cache is populated.
      # Counts both active members and pending invitations.
      #
      # Log-only. The plan values (`role_*_per_org`, `total_members_per_org`)
      # are informational for operators; reaching one writes a log line.
      def note_member_counts
        return unless @organization.respond_to?(:at_limit?)
        return unless @organization.entitlements.any?

        role_resource = ROLE_LIMIT_RESOURCES[@role]
        if role_resource
          role_count = @organization.member_count_by_role(@role) +
                       @organization.pending_invitation_count_by_role(@role)
          note_member_count(role_resource, role_count)
        end

        total_count = @organization.member_count + @organization.pending_invitation_count
        note_member_count('total_members_per_org', total_count)
      end

      def note_member_count(resource, count)
        return unless @organization.at_limit?(resource, count)

        OT.info "[CreateInvitation] Org #{@organization.extid} at or past #{resource} (count: #{count})"
      end
    end
  end
end
