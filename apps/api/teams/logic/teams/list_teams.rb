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

        @teams = cust.team_instances

        OT.ld "[ListTeams] Found #{@teams.size} teams"

        success_data
      end

      # TODO: Replace with safe_dump
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
