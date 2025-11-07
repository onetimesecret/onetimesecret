# apps/api/teams/logic/teams/create_team.rb

module TeamAPI::Logic
  module Teams
    class CreateTeam < TeamAPI::Logic::Base
      attr_reader :team, :display_name, :description

      def process_params
        @display_name = params['display_name'].to_s.strip
        @description = params['description'].to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: 'user_id', error_type: :unauthorized) if cust.anonymous?

        # Validate display_name
        if display_name.empty?
          raise_form_error('Team name is required', field: 'display_name', error_type: :missing)
        end

        if display_name.length < 1
          raise_form_error('Team name must be at least 1 character', field: 'display_name', error_type: :invalid)
        end

        if display_name.length > 100
          raise_form_error('Team name must be less than 100 characters', field: 'display_name', error_type: :invalid)
        end

        # Description is optional but limit length if provided
        if !description.empty? && description.length > 500
          raise_form_error('Description must be less than 500 characters', field: 'description', error_type: :invalid)
        end
      end

      def process
        OT.ld "[CreateTeam] Creating team '#{display_name}' for user #{cust.custid}"

        # Create team using class method
        @team = Onetime::Team.create!(display_name, cust)

        # Set description if provided
        if !description.empty?
          @team.description = description
          @team.save
        end

        OT.info "[CreateTeam] Created team #{@team.teamid}"

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
            created_at: team.created,
            updated_at: team.updated,
            current_user_role: 'owner',
          },
        }
      end

      def form_fields
        {
          display_name: display_name,
          description: description,
        }
      end
    end
  end
end
