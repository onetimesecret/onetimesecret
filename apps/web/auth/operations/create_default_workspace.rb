# apps/web/auth/operations/create_default_workspace.rb
#
# frozen_string_literal: true

#
# Creates a default Organization for a new customer during registration.
# This ensures every user has a workspace ready, even if they're on an individual plan.
#
# Note: The org is hidden from individual plan users in the frontend via
# plan-based feature flags, but the infrastructure exists for seamless upgrades.
#

module Auth
  module Operations
    class CreateDefaultWorkspace
      include Onetime::LoggerMethods

      # @param customer [Onetime::Customer] The customer for whom to create workspace
      def initialize(customer:)
        @customer = customer
      end

      # Executes the workspace creation operation
      # @return [Hash] Contains the created organization
      def call
        unless @customer
          auth_logger.error '[create-default-workspace] Customer is nil!'
          return nil
        end

        if workspace_already_exists?
          auth_logger.debug "[create-default-workspace] Workspace already exists for customer #{@customer.custid}"
          return nil
        end

        org = create_default_organization

        auth_logger.info "[create-default-workspace] Created workspace for #{@customer.custid}: org=#{org.objid}"

        { organization: org }
      end

      private

      # Check if customer already has an organization (e.g., via invite)
      # @return [Boolean]
      def workspace_already_exists?
        return false unless @customer

        # Use Familia v2 auto-generated reverse collection method
        # This uses the participation index for O(1) lookup instead of iterating
        org_count = @customer.organization_instances.count
        has_org   = org_count > 0

        auth_logger.info "[create-default-workspace] Customer #{@customer.custid} has #{org_count} organizations"

        if has_org
          auth_logger.info "[create-default-workspace] Customer #{@customer.custid} already has organization, skipping"
        end

        has_org
      end

      # Creates the default organization for the customer
      # @return [Onetime::Organization]
      def create_default_organization
        org = Onetime::Organization.create!(
          'Default Organization',  # Not shown to individual plan users
          @customer,
          @customer.email,
        )

        # Mark as default workspace (prevents deletion)
        org.is_default! true

        org
      rescue StandardError => ex
        auth_logger.error "[create-default-workspace] Failed to create organization: #{ex.message}"
        raise
      end
    end
  end
end
