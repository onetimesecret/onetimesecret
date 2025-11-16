# apps/api/teams/logic/teams/delete_team.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Teams
    class DeleteTeam < TeamAPI::Logic::Base
      attr_reader :team

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

        # Verify user is owner
        verify_team_owner(@team)

        # Prevent deletion of default teams
        if @team.is_default
          raise_form_error('Cannot delete default team', field: :extid, error_type: :forbidden)
        end
      end

      def process
        OT.ld "[DeleteTeam] Deleting team #{@team_id} for user #{cust.custid}"

        # Get team info before deletion
        @team.extid
        display_name = @team.display_name

        # Remove all members first
        members = @team.list_members
        members.each do |member|
          @team.remove_member(member)
        end

        # Remove from global instances set
        Onetime::Team.instances.rem(team_id)

        # Delete the team
        @team.destroy!

        OT.info "[DeleteTeam] Deleted team #{team_id} (#{display_name})"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          deleted: true,
          team_id: @team_id,
        }
      end

      def form_fields
        {
          team_id: @team_id,
        }
      end
    end
  end
end
