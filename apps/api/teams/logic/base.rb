# apps/api/teams/logic/base.rb
#
# frozen_string_literal: true

# Team API Logic Base Class
#
# Extends V2 logic with modern API patterns for Team API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Team API uses same modern conventions as Account API for consistency.

require_relative '../../v2/logic/base'

module TeamAPI
  module Logic
    class Base < V2::Logic::Base
      # Validation constants
      MAX_DISPLAY_NAME_LENGTH = 100
      MIN_DISPLAY_NAME_LENGTH = 3
      MAX_DESCRIPTION_LENGTH = 500
      # Team API-specific serialization helper
      #
      # Converts Familia model to JSON hash with native types.
      # Unlike v2's safe_dump which converts all primitives to strings,
      # this preserves JSON types from Familia v2's native storage.
      #
      # @param model [Familia::Horreum] Model instance to serialize
      # @return [Hash] JSON-serializable hash with native types
      def json_dump(model)
        return nil if model.nil?

        # Familia v2 models store fields as JSON types already
        # We just need to convert the model to a hash without string coercion
        model.to_h
      end

      # Override safe_dump to use JSON types in Team API
      #
      # This allows Team logic classes to inherit from v2 but get JSON serialization
      # without modifying v2 behavior.
      alias safe_dump json_dump

      # Transform v2 response data to Team API format
      #
      # Team API changes (same as Account API):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Team API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Team API
        team_data = v2_data.dup

        # Remove success field (Team API uses HTTP status codes)
        team_data.delete(:success)
        team_data.delete('success')

        # Rename custid to user_id (modern naming)
        if team_data.key?(:custid)
          team_data[:user_id] = team_data.delete(:custid)
        elsif team_data.key?('custid')
          team_data['user_id'] = team_data.delete('custid')
        end

        team_data
      end

      protected

      # Verify current user owns the team
      def verify_team_owner(team)
        unless team.owner?(cust)
          raise_form_error('Only team owner can perform this action', field: :teamid, error_type: :forbidden)
        end
      end

      # Verify current user is a team member
      def verify_team_member(team)
        unless team.member?(cust)
          raise_form_error('You must be a team member to perform this action', field: :teamid, error_type: :forbidden)
        end
      end

      # Load team and verify it exists
      def load_team(teamid)
        team = Onetime::Team.load(teamid)
        raise_not_found("Team not found: #{teamid}") if team.nil?
        team
      end
    end
  end
end
