# apps/api/organizations/logic/members/update_member_role.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Members
    # Update a member's role within an organization
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
      VALID_ROLES = %w[member admin].freeze

      attr_reader :organization, :target_member, :target_membership, :new_role, :old_role

      def process_params
        @extid = params['extid']
        @member_extid = params['member_extid']
        @new_role = params['role'].to_s.strip.downcase
      end

      def raise_concerns
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        @organization = load_organization(@extid)

        # Only owners can change roles
        verify_organization_owner(@organization)

        # Load target member
        @target_member = load_member(@member_extid)
        @target_membership = load_membership(@organization, @target_member)

        # Validate role
        validate_role_change!
      end

      def process
        # Capture old role BEFORE updating (for audit log and response)
        @old_role = @target_membership.role

        OT.ld "[UpdateMemberRole] Changing role for #{@target_member.extid} from #{@old_role} to #{@new_role}"

        @target_membership.role = @new_role
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
          user_id: cust.objid,
          organization_id: @organization.extid,
          record: {
            id: @target_member.extid,
            email: @target_member.email,
            role: @target_membership.role,
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
        raise_not_found("Member not found: #{extid}") if member.nil?
        member
      end

      # Load membership record for org + member
      def load_membership(organization, member)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid,
          member.objid
        )
        raise_not_found('Member not found in this organization') if membership.nil?
        raise_form_error('Member is not active') unless membership.active?
        membership
      end

      # Validate the requested role change
      def validate_role_change!
        # Validate role value
        unless VALID_ROLES.include?(@new_role)
          raise_form_error(
            "Invalid role. Must be one of: #{VALID_ROLES.join(', ')}",
            field: :role
          )
        end

        # Cannot change owner's role via this endpoint
        if @target_membership.owner?
          raise_form_error(
            'Cannot change owner role. Use ownership transfer instead.',
            field: :role
          )
        end

        # No-op check: already has this role
        if @target_membership.role == @new_role
          raise_form_error(
            "Member already has role: #{@new_role}",
            field: :role
          )
        end

        # Cannot set role to owner via this endpoint
        if @new_role == 'owner'
          raise_form_error(
            'Cannot promote to owner. Use ownership transfer instead.',
            field: :role
          )
        end
      end
    end
  end
end
