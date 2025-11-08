# apps/web/auth/operations/create_default_workspace.rb

#
# Creates a default Organization and Team for a new customer during registration.
# This ensures every user has a workspace ready, even if they're on an individual plan.
#
# Note: The org/team are hidden from individual plan users in the frontend via
# plan-based feature flags, but the infrastructure exists for seamless upgrades.
#

module Auth
  module Operations
    class CreateDefaultWorkspace
      include Onetime::Logging

      # @param customer [Onetime::Customer] The customer for whom to create workspace
      def initialize(customer:)
        @customer = customer
      end

      # Executes the workspace creation operation
      # @return [Hash] Contains the created organization and team
      def call
        return if workspace_already_exists?

        org = create_default_organization
        team = create_default_team(org)

        auth_logger.info "[create-default-workspace] Created workspace for #{@customer.custid}: org=#{org.orgid}, team=#{team.teamid}"

        { organization: org, team: team }
      end

      private

      # Check if customer already has an organization (e.g., via invite)
      # @return [Boolean]
      def workspace_already_exists?
        # Check all existing organizations to see if customer is a member
        # Note: This is a simple check for MVP. In production with many orgs,
        # we'd use an index or Familia v2's participations (when fully working)
        has_org = false

        if defined?(Onetime::Organization) && Onetime::Organization.respond_to?(:values)
          org_ids = Onetime::Organization.values.to_a rescue []
          has_org = org_ids.any? do |orgid|
            org = Onetime::Organization.load(orgid)
            org && org.members.member?(@customer.objid)
          end
        end

        if has_org
          auth_logger.info "[create-default-workspace] Customer #{@customer.custid} already has organization, skipping"
        end

        has_org
      end

      # Creates the default organization for the customer
      # @return [Onetime::Organization]
      def create_default_organization
        org = Onetime::Organization.create!(
          "Default Organization",  # Not shown to individual plan users
          @customer,
          @customer.email
        )

        # Mark as default workspace (prevents deletion)
        org.is_default = true
        org.save

        org
      rescue => e
        auth_logger.error "[create-default-workspace] Failed to create organization: #{e.message}"
        raise
      end

      # Creates the default team within the organization
      # @param org [Onetime::Organization]
      # @return [Onetime::Team]
      def create_default_team(org)
        team = Onetime::Team.create!(
          "Default Team",  # Not shown to individual plan users
          @customer,
          org.orgid
        )

        # Mark as default workspace (prevents deletion)
        team.is_default = true
        team.save

        team
      rescue => e
        auth_logger.error "[create-default-workspace] Failed to create team: #{e.message}"
        raise
      end
    end
  end
end
