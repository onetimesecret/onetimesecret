# apps/api/teams/logic/teams/list_teams.rb
#
# frozen_string_literal: true

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

      def success_data
        {
          user_id: cust.objid,
          records: teams.map do |team|
            team.safe_dump.merge(
              current_user_role: team.owner?(cust) ? 'owner' : 'member',
              is_owner: team.owner?(cust),
            )
          end,
          count: teams.length,
        }
      end
    end
  end
end
