# apps/api/teams/logic/teams/update_team.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Teams
    class UpdateTeam < TeamAPI::Logic::Base
      attr_reader :team, :display_name, :description

      def process_params
        @teamid = params['teamid']
        @display_name = params[:display_name].to_s.strip
        @description = params[:description].to_s.strip
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

        # Validate display_name if provided
        if !display_name.empty?
          if display_name.length < MIN_DISPLAY_NAME_LENGTH
            raise_form_error("Team name must be at least #{MIN_DISPLAY_NAME_LENGTH} characters", field: :display_name, error_type: :invalid)
          end

          if display_name.length > MAX_DISPLAY_NAME_LENGTH
            raise_form_error("Team name must be less than #{MAX_DISPLAY_NAME_LENGTH} characters", field: :display_name, error_type: :invalid)
          end
        end

        # Validate description if provided
        if !description.empty? && description.length > MAX_DESCRIPTION_LENGTH
          raise_form_error("Description must be less than #{MAX_DESCRIPTION_LENGTH} characters", field: :description, error_type: :invalid)
        end

        # At least one field must be provided
        if display_name.empty? && description.empty?
          raise_form_error('At least one field (display_name or description) must be provided', field: :display_name, error_type: :missing)
        end
      end

      def process
        OT.ld "[UpdateTeam] Updating team #{@teamid} for user #{cust.custid}"

        # Update fields
        if !display_name.empty?
          @team.display_name = display_name
        end

        if !description.empty?
          @team.description = description
        end

        # Update timestamp and save
        @team.updated = Familia.now.to_i
        @team.save

        OT.info "[UpdateTeam] Updated team #{@teamid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            id: team.teamid,
            display_name: team.display_name,
            description: team.description || '',
            owner_id: team.owner_id,
            member_count: team.member_count,
            is_default: team.is_default || false,
            created_at: team.created,
            updated_at: team.updated,
            current_user_role: 'owner',
          },
        }
      end

      def form_fields
        {
          teamid: @teamid,
          display_name: display_name,
          description: description,
        }
      end
    end
  end
end
