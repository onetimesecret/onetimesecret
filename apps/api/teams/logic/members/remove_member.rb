# apps/api/teams/logic/members/remove_member.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Members
    class RemoveMember < TeamAPI::Logic::Base
      attr_reader :team, :member_to_remove

      def process_params
        @team_id = params['extid']
        @custid = params['custid'].to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate team extid parameter
        raise_form_error('Team ID required', field: :extid, error_type: :missing) if @team_id.to_s.empty?

        # Validate custid parameter
        raise_form_error('Customer ID required', field: :custid, error_type: :missing) if @custid.empty?

        # Load team
        @team = load_team(@team_id)

        # Load member to remove
        @member_to_remove = Onetime::Customer.load(@custid)
        if @member_to_remove.nil?
          raise_form_error("Customer not found: #{@custid}", field: :custid, error_type: :not_found)
        end

        # Check if target is a member
        unless @team.member?(@member_to_remove)
          raise_form_error("User is not a team member", field: :custid, error_type: :not_found)
        end

        # Authorization: owner can remove anyone, members can only remove themselves
        is_owner = @team.owner?(cust)
        is_self = (@member_to_remove.custid == cust.custid)

        unless is_owner || is_self
          raise_form_error('Only team owner can remove other members', field: :custid, error_type: :forbidden)
        end

        # Cannot remove the owner
        if @team.owner?(@member_to_remove)
          raise_form_error('Cannot remove team owner', field: :custid, error_type: :forbidden)
        end
      end

      def process
        OT.ld "[RemoveMember] Removing member #{@custid} from team #{@team_id}"

        # Remove member from team
        @team.remove_member(@member_to_remove)

        # Update team timestamp
        @team.updated = Familia.now.to_i
        @team.save

        OT.info "[RemoveMember] Removed member #{@custid} from team #{@team_id}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          team_id: team.team_id,
          removed: true,
          custid: @custid,
        }
      end

      def form_fields
        {
          extid: @team_id,
          custid: @custid,
        }
      end
    end
  end
end
