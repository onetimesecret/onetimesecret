# apps/api/teams/logic/teams/get_team.rb

module TeamAPI::Logic
  module Teams
    class GetTeam < TeamAPI::Logic::Base
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
        OT.ld "[GetTeam] Getting team #{@teamid} for user #{cust.custid}"

        # Get team members
        @members = @team.list_members

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            id: team.teamid,
            display_name: team.display_name,
            description: team.description,
            owner_id: team.owner_id,
            is_owner: team.owner?(cust),
            member_count: team.member_count,
            created: team.created,
            updated: team.updated,
            members: members.map do |member|
              {
                custid: member.custid,
                email: member.email,
                role: (team.owner?(member) ? 'owner' : 'member'),
              }
            end,
          },
        }
      end
    end
  end
end
