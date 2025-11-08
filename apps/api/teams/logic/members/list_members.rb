# apps/api/teams/logic/members/list_members.rb

module TeamAPI::Logic
  module Members
    class ListMembers < TeamAPI::Logic::Base
      attr_reader :team, :members

      def process_params
        @teamid = params['teamid']
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate teamid parameter
        raise_form_error('Team ID required', field: :teamid, error_type: :missing) if @teamid.to_s.empty?

        # Load team
        @team = load_team(@teamid)

        # Verify user is a member
        verify_team_member(@team)
      end

      def process
        OT.ld "[ListMembers] Listing members for team #{@teamid}"

        # Get all team members
        @members = @team.list_members

        OT.ld "[ListMembers] Found #{@members.size} members"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          teamid: team.teamid,
          records: members.map do |member|
            {
              custid: member.custid,
              email: member.email,
              role: (team.owner?(member) ? 'owner' : 'member'),
              is_current_user: (member.custid == cust.custid),
            }
          end,
          count: members.length,
        }
      end
    end
  end
end
