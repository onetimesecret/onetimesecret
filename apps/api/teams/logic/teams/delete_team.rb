# apps/api/teams/logic/teams/delete_team.rb

module TeamAPI::Logic
  module Teams
    class DeleteTeam < TeamAPI::Logic::Base
      attr_reader :team

      def process_params
        @teamid = params[:teamid]
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate teamid parameter
        raise_form_error('Team ID required', field: :teamid, error_type: :missing) if @teamid.to_s.empty?

        # Load team
        @team = load_team(@teamid)

        # Verify user is owner
        verify_team_owner(@team)
      end

      def process
        OT.ld "[DeleteTeam] Deleting team #{@teamid} for user #{cust.custid}"

        # Get team info before deletion
        teamid = @team.teamid
        display_name = @team.display_name

        # Remove all members first
        members = @team.list_members
        members.each do |member|
          @team.remove_member(member)
        end

        # Remove from global values set
        Onetime::Team.values.rem(teamid)

        # Delete the team
        @team.destroy!

        OT.info "[DeleteTeam] Deleted team #{teamid} (#{display_name})"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          deleted: true,
          teamid: @teamid,
        }
      end

      def form_fields
        {
          teamid: @teamid,
        }
      end
    end
  end
end
