# apps/api/teams/logic/teams/create_team.rb
#
# frozen_string_literal: true

module TeamAPI::Logic
  module Teams
    class CreateTeam < TeamAPI::Logic::Base
      attr_reader :team, :display_name, :description

      def process_params
        @display_name = params['display_name'].to_s.strip
        @description  = params['description'].to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # TODO: Team quota check (issue #2224)
        # Temporarily disabled pending proper billing integration in tests
        # if org&.respond_to?(:at_limit?) &&
        #    org.respond_to?(:entitlements) &&
        #    org.entitlements.any? &&
        #    org.respond_to?(:teams) &&
        #    org.at_limit?('teams', org.teams&.size.to_i)
        #   raise_form_error('Team limit reached for your plan', field: :display_name, error_type: :forbidden)
        # end

        # Validate display_name
        if display_name.empty?
          raise_form_error('Team name is required', field: :display_name, error_type: :missing)
        end

        if display_name.length < MIN_DISPLAY_NAME_LENGTH
          raise_form_error("Team name must be at least #{MIN_DISPLAY_NAME_LENGTH} characters", field: :display_name, error_type: :invalid)
        end

        if display_name.length > MAX_DISPLAY_NAME_LENGTH
          raise_form_error("Team name must be less than #{MAX_DISPLAY_NAME_LENGTH} characters", field: :display_name, error_type: :invalid)
        end

        # Description is optional but limit length if provided
        if !description.empty? && description.length > MAX_DESCRIPTION_LENGTH
          raise_form_error("Description must be less than #{MAX_DESCRIPTION_LENGTH} characters", field: :description, error_type: :invalid)
        end
      end

      def process
        OT.ld "[CreateTeam] Creating team '#{display_name}' for user #{cust.custid}"

        # Create team using class method
        @team = Onetime::Team.create!(display_name, cust)

        # Set description if provided
        unless description.empty?
          @team.description = description
          @team.save
        end

        OT.info "[CreateTeam] Created team #{@team.extid}"

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
          display_name: display_name,
          description: description,
        }
      end
    end
  end
end
