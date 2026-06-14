# apps/api/organizations/logic/members/remove_member.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Members
    # Remove Member
    #
    # @api Removes a member from an organization. Owners can remove admins
    #   and members; admins can only remove members. The owner cannot be
    #   removed (ownership must be transferred first), and you cannot
    #   remove yourself.
    #
    # DELETE /api/organizations/:extid/members/:member_extid
    #
    # Lifecycle (mirrors GitLab Members::DestroyService, Discourse, etc.):
    #   1. Delete the membership record (org.members + customer.participations)
    #   2. Cascade derived state (materialized entitlements, role caches)
    #   3. Log an audit event (who removed whom, when)
    #   4. Do NOT modify the customer's account, login, or role
    #
    # Authorization Rules:
    #   - Owner can remove admins and members (not themselves)
    #   - Admin can remove members only (not other admins or owner)
    #   - Members cannot remove anyone
    #   - Cannot remove the owner (must transfer ownership first)
    #   - Cannot remove yourself (use leave organization instead)
    #
    class RemoveMember < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'memberDelete' }.freeze

      attr_reader :organization, :target_member, :target_membership, :actor_membership

      def process_params
        @extid        = sanitize_identifier(params['extid'])
        @member_extid = sanitize_identifier(params['member_extid'])
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)

        # Load actor's membership to check their role
        @actor_membership = load_actor_membership(@organization)

        # Domain-scoped members cannot perform member operations
        if @actor_membership&.domain_scoped?
          raise_form_error(error_key: 'api.organizations.errors.domain_scoped_forbidden', error_type: :forbidden)
        end

        # Load target member
        @target_member     = load_member(@member_extid)
        @target_membership = load_membership(@organization, @target_member)

        # Validate removal is allowed
        validate_removal!
      end

      def process
        OT.ld "[RemoveMember] Removing #{@target_member.extid} from org #{@organization.extid}"

        target_extid = @target_member.extid

        # Single call handles all cleanup: Familia sorted sets (org.members +
        # customer.participations), OTS app indexes, and the membership hash.
        @target_membership.destroy_with_index_cleanup!

        # Audit log for member removal
        OT.info "[AUDIT] action=member_removed actor=#{cust.extid} target=#{target_extid} " \
                "colonel_override=#{cust.role?(:colonel)} org=#{@organization.extid} " \
                "timestamp=#{Time.now.utc.iso8601}"

        success_data
      end

      def success_data
        {
          deleted: true,
          member_extid: @target_member.extid,
        }
      end

      protected

      # Load actor's membership to determine their permissions
      def load_actor_membership(organization)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid,
          cust.objid,
        )

        # Colonels bypass membership requirement
        if cust.role?(:colonel) && membership.nil?
          OT.info "[AUDIT] action=colonel_membership_bypass actor=#{cust.extid} " \
                  "org=#{organization.extid} timestamp=#{Time.now.utc.iso8601}"
          return nil
        end

        if membership.nil?
          raise_form_error(
            error_key: 'api.organizations.members.errors.must_be_member',
            error_type: :forbidden,
          )
        end

        membership
      end

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
        membership
      end

      # Validate removal is allowed based on role hierarchy
      def validate_removal!
        # Cannot remove owner
        if @target_membership.owner?
          raise_form_error(
            error_key: 'api.organizations.members.errors.cannot_remove_owner',
            error_type: :forbidden,
          )
        end

        # Cannot remove yourself (use leave endpoint instead)
        if @target_member.objid == cust.objid
          raise_form_error(
            error_key: 'api.organizations.members.errors.cannot_remove_self',
            error_type: :forbidden,
          )
        end

        # Colonels can remove anyone (except owner, already checked)
        return if cust.role?(:colonel)

        # Check actor's role permissions
        # Note: @actor_membership is guaranteed non-nil here because:
        # 1. Colonels already returned at line 130
        # 2. Non-colonels without membership would have raised in load_actor_membership
        actor_role  = @actor_membership.role
        target_role = @target_membership.role

        case actor_role
        when 'owner'
          # Owner can remove anyone except themselves (already checked)
          true
        when 'admin'
          # Admin can only remove members, not other admins
          if target_role == 'admin'
            raise_form_error(
              error_key: 'api.organizations.members.errors.admin_cannot_remove_admin',
              error_type: :forbidden,
            )
          end
        else
          # Members cannot remove anyone
          raise_form_error(
            error_key: 'api.organizations.members.errors.no_permission_to_remove',
            error_type: :forbidden,
          )
        end
      end
    end
  end
end
