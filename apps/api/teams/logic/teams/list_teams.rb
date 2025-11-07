# apps/api/teams/logic/teams/list_teams.rb

module TeamAPI::Logic
  module Teams
    class ListTeams < TeamAPI::Logic::Base
      attr_reader :teams

      def process_params
        # No parameters needed - lists all teams for current user
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
      end

      def process
        OT.ld "[ListTeams] Listing teams for user #{cust.custid}"

        # Get all teams where user is owner or member
        # Note: This is a simple implementation. For large scale,
        # consider adding a customer.teams relationship in the model
        all_teams = Onetime::Team.values.members.map { |teamid| Onetime::Team.load(teamid) }.compact

        # Filter to teams where current user is a member
        @teams = all_teams.select { |team| team.member?(cust) }

        OT.ld "[ListTeams] Found #{@teams.size} teams"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          records: teams.map do |team|
            {
              id: team.teamid,
              display_name: team.display_name,
              description: team.description,
              owner_id: team.owner_id,
              is_owner: team.owner?(cust),
              member_count: team.member_count,
              created: team.created,
              updated: team.updated,
            }
          end,
          count: teams.length,
        }
      end
    end
  end
end
