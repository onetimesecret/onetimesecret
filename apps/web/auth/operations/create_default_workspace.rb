# apps/web/auth/operations/create_default_workspace.rb
#
# frozen_string_literal: true

#
# CANONICAL SOURCE FOR DEFAULT WORKSPACE CREATION
#
# Creates a default Organization for a new customer during registration.
# This ensures every user has a workspace ready, even if they're on an individual plan.
#
# Note: The org is hidden from individual plan users in the frontend via
# plan-based feature flags, but the infrastructure exists for seamless upgrades.
#
# ## Callers
#
# All workspace creation now routes through this operation:
#   - lib/onetime/logic/organization_context.rb - Lazy creation in auth_org
#   - apps/web/billing/logic/welcome.rb - Stripe payment link/checkout handlers
#   - apps/web/billing/controllers/plans.rb - Billing flow fallback
#   - apps/web/billing/operations/webhook_handlers/checkout_completed.rb
#
# Note: lib/onetime/application/organization_loader.rb is READ-ONLY during
# authentication and no longer creates workspaces (see #2880).
#

module Auth
  module Operations
    class CreateDefaultWorkspace
      include Onetime::LoggerMethods

      # @param customer [Onetime::Customer] The customer for whom to create workspace
      # @param require_verification [Boolean] When true, defer claiming a
      #   pending federated subscription until the customer's email is verified.
      #   The default workspace is ALWAYS created regardless of this flag; only
      #   the federated-subscription claim is gated.
      #
      #   SECURITY: This flag closes a benefit-theft gap. `apply_pending_federation!`
      #   runs from the standard email/password `after_create_account` hook —
      #   BEFORE the user has proven ownership of the email. Without gating, an
      #   attacker who knows a paying subscriber's email could register that
      #   email in another region and, at account-creation time, claim and
      #   destroy the victim's PendingFederatedSubscription. Callers on the
      #   standard signup path pass `require_verification: true` so the claim is
      #   deferred to `after_verify_account`. Pre-verified/trusted callers (SSO
      #   IdP-verified, invite-token, post-payment billing, authenticated lazy
      #   creation) leave it at the default (false) and claim immediately.
      def initialize(customer:, require_verification: false)
        @customer             = customer
        @require_verification = require_verification
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

      # Claim a deferred pending federated subscription for a customer whose
      # default workspace already exists.
      #
      # Invoked from `after_verify_account` once a standard email/password
      # signup proves email ownership. The default workspace was created at
      # signup (with the federation claim deferred); here we locate that
      # workspace and apply any pending federated subscription to it.
      #
      # Idempotent and safe to call unconditionally:
      #   - no-op if the customer is missing/unverified,
      #   - no-op if the customer has no organization,
      #   - no-op if there is no pending record (or it was already claimed and
      #     consumed on a prior verification), because the pending record is
      #     destroyed on first successful claim.
      #
      # @param customer [Onetime::Customer] verified customer
      # @return [Boolean] True if a pending subscription was applied
      def self.claim_pending_federation_for(customer)
        new(customer: customer).claim_pending_federation
      end

      # Instance form of {.claim_pending_federation_for}.
      #
      # @return [Boolean] True if a pending subscription was applied
      def claim_pending_federation
        return false unless @customer

        # Only claim once the email is verified. This is the whole point of the
        # deferral: the after_verify_account hook has just marked the customer
        # verified before calling here.
        unless @customer.verified?
          auth_logger.debug '[create-default-workspace] claim_pending_federation: customer not verified, skipping'
          return false
        end

        org = default_organization_for(@customer)
        unless org
          auth_logger.debug '[create-default-workspace] claim_pending_federation: no organization for customer, skipping'
          return false
        end

        apply_pending_federation!(org)
      end

      private

      # Locate the customer's default workspace (created at signup). Falls back
      # to the customer's first organization when no explicit default is marked.
      #
      # @param customer [Onetime::Customer]
      # @return [Onetime::Organization, nil]
      def default_organization_for(customer)
        orgs = customer.organization_instances.to_a
        return nil if orgs.empty?

        orgs.find { |org| org.is_default == true || org.is_default.to_s == 'true' } || orgs.first
      end

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
      rescue Onetime::Problem => ex
        raise unless ex.message.include?('Organization exists')

        # Org exists in the email index but customer has no membership link
        # (e.g., incomplete prior creation, data inconsistency after SSO).
        # Find the existing org and repair the membership.
        existing = Onetime::Organization.find_by_contact_email(@customer.email)
        raise unless existing

        if existing.member_count > 0
          auth_logger.warn "[create-default-workspace] Existing org #{existing.extid} already has members, skipping adoption for #{@customer.custid}"
          raise
        end

        auth_logger.info "[create-default-workspace] Adopting orphaned org #{existing.extid} for #{@customer.custid}"
        existing.add_members_instance(@customer, through_attrs: { role: 'owner' })
        existing
      rescue StandardError => ex
        auth_logger.error "[create-default-workspace] Failed to create organization: #{ex.message}"
        raise
      end

      # Check for and apply pending federated subscription
      #
      # When a Stripe webhook fired before this account existed, the subscription
      # state was stored keyed by email_hash. When a matching account later
      # appears in this region we can apply those benefits to its organization.
      #
      # IMPORTANT: account creation does NOT prove email ownership. For the
      # standard email/password signup, this method runs from
      # `after_create_account`, before the verification email is even sent. To
      # prevent an attacker from claiming a victim's pending subscription by
      # merely registering the victim's email here, the claim is gated on
      # verification when the caller sets `require_verification: true` (see
      # #initialize). Callers on that path receive the benefit once the user
      # verifies, via `after_verify_account` → {.claim_pending_federation_for}.
      # Pre-verified callers (SSO, invite, post-payment billing, authenticated
      # lazy creation) run this immediately with the gate disabled.
      #
      # @param org [Onetime::Organization] Newly created organization
      # @return [Boolean] True if pending subscription was applied
      #
      def apply_pending_federation!(org)
        # Verification gate: on the standard signup path the email is not yet
        # verified at account-creation time. Defer the claim (leaving the
        # PendingFederatedSubscription intact) until the user verifies; the
        # after_verify_account hook re-invokes the claim once verified.
        if @require_verification && !@customer&.verified?
          auth_logger.info '[create-default-workspace] Deferring federated subscription claim until email is verified',
            { org: org.extid }
          return false
        end

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

        # Lazy load billing model (auth can operate without billing plugin)
        begin
          require_relative '../../billing/models/pending_federated_subscription'
        rescue LoadError
          auth_logger.debug '[create-default-workspace] Billing plugin not available, skipping federation check'
          return false
        end

        # Guard: billing module may not be loaded
        return false unless defined?(Billing::PendingFederatedSubscription)

        # Check for pending subscription
        pending = Billing::PendingFederatedSubscription.find_by_email_hash(org.email_hash)
        return false unless pending
        return false unless pending.active?

        # Apply subscription benefits
        org.subscription_status     = pending.subscription_status
        org.planid                  = pending.planid if pending.planid
        org.subscription_period_end = pending.subscription_period_end
        org.mark_subscription_federated!

        # Materialize entitlements from the claimed plan (Phase 2)
        # PendingFederatedSubscription stores planid but not entitlements,
        # so we materialize now that the org has its planid set.
        begin
          require_relative '../../billing/operations/apply_subscription_to_org'
          Billing::Operations::ApplySubscriptionToOrg.materialize_entitlements_for_org(org)
        rescue LoadError
          auth_logger.debug '[create-default-workspace] Billing operations not available for materialization'
        end

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
