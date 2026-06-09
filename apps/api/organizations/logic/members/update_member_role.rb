# apps/api/organizations/logic/members/update_member_role.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Members
    # Update Member Role
    #
    # @api Changes a member's role within an organization. Only organization
    #   owners can change roles. Valid target roles are "member" and "admin".
    #   Returns the updated member record with both the new and previous role.
    #
    # PATCH /api/organizations/:extid/members/:member_extid/role
    #
    # Role Hierarchy: owner > admin > member
    #
    # Authorization Rules:
    #   - Only owners can promote to/demote from admin
    #   - Cannot change owner's role (must transfer ownership)
    #   - Cannot demote the last owner
    #   - Admins cannot change roles (only owners can)
    #
    # Params:
    #   - role (required): New role ('member' or 'admin')
    #
    class UpdateMemberRole < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'member' }.freeze

      VALID_ROLES = %w[member admin].freeze

      attr_reader :organization, :target_member, :target_membership, :new_role, :old_role

      def process_params
        @extid        = sanitize_identifier(params['extid'])
        @member_extid = sanitize_identifier(params['member_extid'])
        @new_role     = sanitize_plain_text(params['role']).downcase
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)

        # Only users with manage_org entitlement can change roles
        require_entitlement_in!(@organization, 'manage_org')

        # Domain-scoped members cannot perform member operations
        actor_membership = Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, cust.objid)
        if actor_membership&.domain_scoped?
          raise_form_error(error_key: 'api.organizations.errors.domain_scoped_forbidden', error_type: :forbidden)
        end

        # Load target member
        @target_member     = load_member(@member_extid)
        @target_membership = load_membership(@organization, @target_member)

        # Validate role
        validate_role_change!
      end

      def process
        # Capture old role BEFORE updating (for audit log and response)
        @old_role = @target_membership.role

        OT.ld "[UpdateMemberRole] Changing role for #{@target_member.extid} from #{@old_role} to #{@new_role}"

        @target_membership.change_role!(@new_role)
        @target_membership.updated_at = Familia.now.to_f
        @target_membership.save

        # Audit log for role changes
        OT.info "[AUDIT] action=role_change actor=#{cust.extid} target=#{@target_member.extid} " \
                "old_role=#{@old_role} new_role=#{@new_role} colonel_override=#{cust.role?(:colonel)} " \
                "org=#{@organization.extid} timestamp=#{Time.now.utc.iso8601}"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization_id: @organization.extid,
          record: {
            extid: @target_member.extid,
            email: @target_member.email,
            role: @target_membership.role,
            joined_at: @target_membership.joined_at,
            is_owner: @target_membership.owner?,
            is_current_user: @target_member.objid == cust.objid,
            previous_role: @old_role,
          },
        }
      end

      def form_fields
        { role: @new_role }
      end

      protected

      # Load member by external ID
      def load_member(extid)
        member = Onetime::Customer.find_by_extid(extid)
        if member.nil?
          raise_not_found(
            error_key: 'api.organizations.members.errors.member_not_found',
            args: { extid: extid },
          )
        end
        member
      end

      # Load membership record for org + member
      def load_membership(organization, member)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid,
          member.objid,
        )
        if membership.nil?
          raise_not_found(error_key: 'api.organizations.members.errors.member_not_in_organization')
        end
        unless membership.active?
          raise_form_error(error_key: 'api.organizations.members.errors.member_not_active', error_type: :invalid)
        end
        membership
      end

      # Validate the requested role change
      def validate_role_change!
        # Validate role value
        unless VALID_ROLES.include?(@new_role)
          raise_form_error(
            error_key: 'api.organizations.members.errors.invalid_role_value',
            args: { roles: VALID_ROLES.join(', ') },
            field: :role,
            error_type: :invalid,
          )
        end

        # Cannot change owner's role via this endpoint
        if @target_membership.owner?
          raise_form_error(
            error_key: 'api.organizations.members.errors.cannot_change_owner_role',
            field: :role,
            error_type: :forbidden,
          )
        end

        # No-op check: already has this role
        if @target_membership.role == @new_role
          raise_form_error(
            error_key: 'api.organizations.members.errors.member_already_has_role',
            args: { role: @new_role },
            field: :role,
            error_type: :conflict,
          )
        end

        # Cannot set role to owner via this endpoint
        return unless @new_role == 'owner'

        raise_form_error(
          error_key: 'api.organizations.members.errors.cannot_promote_to_owner',
          field: :role,
          error_type: :forbidden,
        )
      end
    end
  end
end
