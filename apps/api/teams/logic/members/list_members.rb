# apps/api/teams/logic/members/list_members.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Members
    class ListMembers < TeamAPI::Logic::Base
      attr_reader :team, :members

      def process_params
        @team_id = params['extid']
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate team extid parameter
        raise_form_error('Team ID required', field: :extid, error_type: :missing) if @team_id.to_s.empty?

        # Load team
        @team = load_team(@team_id)

        # Verify user is a member
        verify_team_member(@team)
      end

      def process
        OT.ld "[ListMembers] Listing members for team #{@team_id}"

        # Get all team members
        @members = @team.list_members

        OT.ld "[ListMembers] Found #{@members.size} members"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          team_id: team.team_id,
          records: members.map do |member|
            {
              id: member.custid,
              team_id: team.team_id,
              user_id: member.custid,
              email: member.email,
              role: (team.owner?(member) ? 'owner' : 'member'),
              status: 'active',
              created_at: member.created || Familia.now.to_i,
              updated_at: member.updated || Familia.now.to_i,
            }
          end,
          count: members.length,
        }
      end
    end
  end
end
