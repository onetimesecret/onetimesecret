# apps/api/teams/logic/teams/update_team.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Teams
    class UpdateTeam < TeamAPI::Logic::Base
      attr_reader :team, :display_name, :description

      def process_params
        @team_id      = params['extid']
        @display_name = params['display_name'].to_s.strip
        @description  = params['description'].to_s.strip
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

        # Validate display_name if provided
        unless display_name.empty?
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
        OT.ld "[UpdateTeam] Updating team #{@team_id} for user #{cust.custid}"

        # Update fields
        unless display_name.empty?
          @team.display_name = display_name
        end

        unless description.empty?
          @team.description = description
        end

        # Update timestamp and save
        @team.updated = Familia.now.to_i
        @team.save

        OT.info "[UpdateTeam] Updated team #{@team_id}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: team.safe_dump.merge(
            current_user_role: 'owner',
            is_owner: true,
          ),
        }
      end

      def form_fields
        {
          extid: @team_id,
          display_name: display_name,
          description: description,
        }
      end
    end
  end
end
