# apps/web/auth/operations/create_default_workspace.rb
#
# frozen_string_literal: true

require_relative '../../billing/models/pending_federated_subscription'

#
# CANONICAL SOURCE FOR DEFAULT WORKSPACE CREATION
#
# Creates a default Organization for a new customer during registration.
# This ensures every user has a workspace ready, even if they're on an individual plan.
#
# Note: The org is hidden from individual plan users in the frontend via
# plan-based feature flags, but the infrastructure exists for seamless upgrades.
#
# ## Why Fallbacks Exist Elsewhere
#
# Several other locations have "self-healing" fallback code that creates default
# workspaces when one doesn't exist. This compensates for edge cases where this
# canonical flow wasn't triggered (e.g., legacy accounts, failed transactions,
# race conditions during signup, or Stripe webhook replays).
#
# Fallback locations (all should use `is_default: true` atomically):
#   - lib/onetime/application/organization_loader.rb - Request-time self-healing
#   - apps/web/billing/logic/welcome.rb - Stripe payment link/checkout handlers
#   - apps/web/billing/controllers/plans.rb - Billing flow fallback
#   - apps/web/billing/operations/webhook_handlers/checkout_completed.rb
#
# Ideally, this class would be the single entry point and fallbacks wouldn't
# be needed. Until the signup flow guarantees workspace creation, the fallbacks
# provide resilience for production edge cases.
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
          'Default Workspace',  # Not shown to individual plan users
          @customer,
          @customer.email,
        )

        # Mark as default workspace (prevents deletion)
        org.is_default! true

        # Check for pending federated subscription (cross-region benefit)
        apply_pending_federation!(org)

        org
      rescue StandardError => ex
        auth_logger.error "[create-default-workspace] Failed to create organization: #{ex.message}"
        raise
      end

      # Check for and apply pending federated subscription
      #
      # When a Stripe webhook fired before this account existed, the subscription
      # state was stored keyed by email_hash. Now that the user has verified their
      # email (by creating an account), we can apply those benefits.
      #
      # @param org [Onetime::Organization] Newly created organization
      # @return [Boolean] True if pending subscription was applied
      #
      def apply_pending_federation!(org)
        # Ensure billing_email is set (may not be set by Organization.create!)
        org.billing_email ||= org.contact_email || @customer.email
        return false if org.billing_email.to_s.empty?

        # Compute org's email_hash for matching
        begin
          org.compute_email_hash!
        rescue StandardError => ex
          auth_logger.warn '[create-default-workspace] Failed to compute email_hash (federation disabled?)',
            { error: ex.message }
          return false
        end

        return false if org.email_hash.to_s.empty?

        # Check for pending subscription
        pending = Billing::PendingFederatedSubscription.find_by_email_hash(org.email_hash)
        return false unless pending
        return false unless pending.active?

        # Apply subscription benefits
        org.subscription_status     = pending.subscription_status
        org.planid                  = pending.planid if pending.planid
        org.subscription_period_end = pending.subscription_period_end
        org.mark_subscription_federated!
        org.save

        auth_logger.info '[create-default-workspace] Applied pending federated subscription',
          {
            org: org.extid,
            hash_prefix: org.email_hash[0..7],
            plan: pending.planid,
            status: pending.subscription_status,
          }

        # Consume the pending record (it's been used)
        pending.destroy!

        true
      rescue StandardError => ex
        # Log but don't fail account creation - federation is secondary
        auth_logger.error '[create-default-workspace] Failed to apply pending federation',
          { error: ex.message, org: org.extid }
        false
      end
    end
  end
end
