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
        @extid = params['extid']
        @email = params['email'].to_s.strip.downcase
        @role  = params['role'].to_s.strip
        @role  = 'member' if @role.empty?
      end

      def raise_concerns
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        @organization = load_organization(@extid)
        verify_organization_admin(@organization)

        # Check member quota before other validations
        check_member_quota!

        # Validate email
        raise_form_error('Email is required', field: :email) if @email.empty?
        raise_form_error('Invalid email format', field: :email) unless valid_email?(@email)

        # Validate role
        unless %w[member admin].include?(@role)
          raise_form_error('Role must be member or admin', field: :role)
        end

        # Owners cannot be invited (must be assigned directly)
        if @role == 'owner'
          raise_form_error('Cannot invite as owner', field: :role)
        end

        # Check if user is already a member
        existing_customer = Onetime::Customer.find_by_email(@email)
        if existing_customer && @organization.member?(existing_customer)
          raise_form_error('User is already a member of this organization', field: :email)
        end

        # Check for existing pending invitation
        existing_invite = Onetime::OrganizationMembership.find_by_org_email(
          @organization.objid, @email
        )
        if existing_invite&.pending?
          raise_form_error('Invitation already pending for this email', field: :email)
        end
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
        Onetime::Jobs::Publisher.enqueue_email(
          :organization_invitation,
          {
            invited_email: @email,
            organization_name: @organization.display_name,
            inviter_email: cust.email,
            role: @role,
            invite_token: @membership.token,
          },
          fallback: :sync,
        )

        OT.info "[CreateInvitation] Created invitation #{@membership.objid} for #{OT::Utils.obscure_email(@email)}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
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
          'Member limit reached. Upgrade your plan to invite more members.',
          field: 'email',
          error_type: :upgrade_required,
        )
      end

      # Verify current user has admin privileges in the organization
      def verify_organization_admin(organization)
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: 'Only organization owners and admins can create invitations',
        )
      end

      # Check if user is an organization admin
      def organization_admin?(organization)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, cust.objid
        )
        membership&.admin?
      end

      # Basic email validation
      def valid_email?(email)
        email =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
      end
    end
  end
end
