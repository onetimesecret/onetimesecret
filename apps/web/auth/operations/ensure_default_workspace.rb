# apps/web/auth/operations/ensure_default_workspace.rb
#
# frozen_string_literal: true

require 'auth/operations/workspace_collision'

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
    class EnsureDefaultWorkspace
      include Onetime::LoggerMethods

      PROVISIONING_FAILURE_CODE = 'default_workspace_collision'

      # Per-customer creation lock. Organization.create! is not atomic (index
      # reserve → save → add member; is_default! lands later still), so two
      # concurrent requests for the same org-less customer — parallel SPA calls
      # right after login — used to interleave: the loser classified the
      # winner's half-built org as :phantom_index (and compare-and-deleted the
      # winner's LIVE reservation, then minted a second workspace) or as
      # :live_members (and latched a permanent 409 next to a working
      # workspace). A Familia::Lock (SET NX EX, token-checked release) on
      # Customer.org_creation_lock_key makes the create path single-file — and
      # single-file against OrganizationAPI CreateOrganization too, which locks
      # the same key. The TTL only bounds a holder that died mid-create.
      CREATE_LOCK_TTL      = 15
      # A contender never classifies a collision that may be the customer's own
      # in-flight org: it waits for the holder's workspace to appear and
      # otherwise fails retryable. Total wait stays well under any proxy
      # timeout and under CREATE_LOCK_TTL.
      CREATE_LOCK_WAIT     = 2.0
      CREATE_LOCK_INTERVAL = 0.1

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
      #
      #   RESIDUAL (verify_account disabled): the standard-signup caller derives
      #   this flag from `Onetime.auth_config.verify_account_enabled?`, so when a
      #   deployment turns email verification OFF the flag is false and the claim
      #   still happens immediately with no proof of email ownership. Gating on
      #   `verified?` cannot help there: with verify_account disabled the Redis
      #   `customer.verified` flag is never set true for standard signups and
      #   there is no `after_verify_account` hook to defer to, so requiring
      #   verification would silently disable federated claims for that config.
      #   We deliberately preserve the immediate-claim behavior and instead emit
      #   a loud security-audit log for every unverified immediate claim under a
      #   verify-disabled deployment (see {#apply_pending_federation!} and
      #   {#unverified_immediate_claim?}) so operators can detect abuse. Fully
      #   closing this residual (e.g. an opt-in "require verified claim" flag)
      #   would degrade the feature for those deployments and is a product
      #   decision, not a default.
      # @param stripe_customer_id [String, nil] when a checkout completion is
      #   driving the creation, the checkout's Stripe customer. The new org is
      #   created already holding that unique-index claim, so two completion
      #   surfaces racing on the same checkout elect one creator instead of
      #   both minting a workspace (see
      #   Billing::CheckoutTargetResolver.adopt_claimed_workspace). Ignored
      #   when blank, which is every non-billing caller.
      # @param claim_pending_federation [Boolean] When false, decline to claim a
      #   PendingFederatedSubscription: create the workspace and leave the
      #   pending record intact.
      #
      #   Only the checkout-completion surfaces pass false. They arrive holding
      #   a paid LOCAL subscription that they apply to this workspace moments
      #   later, so claiming here would consume the customer's cross-region
      #   record — destroying the only copy of it — to deliver a benefit they
      #   are about to receive anyway, and would leave the org marked federated
      #   for a subscription it actually owns (#4212).
      #
      #   Distinct from require_verification, which DEFERS the claim to
      #   after_verify_account. This flag declines it outright, because a
      #   checkout completion has no later re-claim to defer to. The pending
      #   record survives for the surface that can resolve it properly: the
      #   next federated subscription webhook, which reads the plan from
      #   subscription metadata.
      def initialize(customer:, require_verification: false, stripe_customer_id: nil,
                     claim_pending_federation: true)
        @customer                 = customer
        @require_verification     = require_verification
        @stripe_customer_id       = stripe_customer_id
        @claim_pending_federation = claim_pending_federation
      end

      # Executes the workspace creation operation
      # @return [Hash] Contains the created organization
      def call
        unless @customer
          auth_logger.error '[create-default-workspace] Customer is nil!'
          return nil
        end

        return converge_on_existing_workspace if workspace_already_exists?

        lock  = Familia::Lock.new(Onetime::Customer.org_creation_lock_key(@customer.objid))
        token = lock.acquire(ttl: CREATE_LOCK_TTL)
        return await_concurrent_provisioning unless token

        provision_under_lock(lock, token)
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
      #
      # @param quiet [Boolean] log at debug instead of info. The contender
      #   poll loop reads this every CREATE_LOCK_INTERVAL, which at info would
      #   be up to ~20 lines per contended request; the normal path keeps its
      #   single info line.
      # @return [Boolean]
      def workspace_already_exists?(quiet: false)
        return false unless @customer

        # Use Familia v2 auto-generated reverse collection method
        # This uses the participation index for O(1) lookup instead of iterating
        org_count = @customer.organization_instances.count
        has_org   = org_count > 0

        auth_logger.public_send(
          quiet ? :debug : :info,
          "[create-default-workspace] Customer #{@customer.custid} has #{org_count} organizations" \
          "#{'; already has organization, skipping' if has_org}",
        )

        has_org
      end

      # A workspace that exists is the whole invariant; a latch next to it is
      # stale by definition, so every exists-path clears it.
      # @return [nil] the historical "already existed" result
      def converge_on_existing_workspace
        @customer.clear_provisioning_failure!
        auth_logger.debug "[create-default-workspace] Workspace already exists for customer #{@customer.custid}"
        nil
      end

      # @param lock [Familia::Lock] the held per-customer creation lock
      # @param token [String] the token #call acquired it with
      # @return [Hash, nil] see #call
      def provision_under_lock(lock, token)
        # Double-checked: the previous holder may have provisioned between our
        # first check and the lock.
        return converge_on_existing_workspace if workspace_already_exists?

        org = create_default_organization
        @customer.clear_provisioning_failure!

        auth_logger.info "[create-default-workspace] Created workspace for #{@customer.custid}: org=#{org.objid}"

        { organization: org }
      ensure
        release_create_lock(lock, token)
      end

      # Familia::Lock#release is token-checked: a holder that outlived the TTL
      # cannot delete the lock a successor now owns.
      def release_create_lock(lock, token)
        lock.release(token)
      rescue StandardError => ex
        # The TTL reclaims it; failing the request over a release would turn a
        # provisioned workspace into an error response.
        auth_logger.warn '[create-default-workspace] Could not release create lock',
          { customer: @customer.extid, error: ex.class.name }
      end

      # Another request is provisioning this customer right now. Never
      # classify (the collision would be the customer's own in-flight org) and
      # never latch: wait a bounded time for that workspace, otherwise fail
      # retryable so the next request finds it.
      # @return [Hash] the holder's workspace
      # @raise [Onetime::AccountProvisioningUnavailable] when nothing appears
      def await_concurrent_provisioning
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + CREATE_LOCK_WAIT
        loop do
          sleep CREATE_LOCK_INTERVAL
          if workspace_already_exists?(quiet: true)
            converge_on_existing_workspace
            return { organization: default_organization_for(@customer) }
          end
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end

        auth_logger.warn '[create-default-workspace] Concurrent provisioning did not complete within wait; retryable',
          { customer: @customer.extid, waited_seconds: CREATE_LOCK_WAIT }
        raise Onetime::AccountProvisioningUnavailable.new(reason: :provisioning_in_progress)
      end

      # Creates the default organization for the customer
      # @return [Onetime::Organization]
      def create_default_organization(retry_phantom: true)
        org = Onetime::Organization.create!(
          'Default Workspace',  # Not shown to individual plan users
          @customer,
          @customer.email,
          **Onetime::Organization.stripe_claim_fields(@stripe_customer_id),
        )

        # Mark as default workspace (prevents deletion)
        org.is_default! true

        # Check for pending federated subscription (cross-region benefit)
        apply_pending_federation!(org)

        org
      rescue Onetime::OrganizationExists
        collision = WorkspaceCollision.new(email: @customer.email, customer: @customer).call

        # :unreadable is "could not determine" (a datastore error mid-scan), not
        # an account state. Latching it would turn one Redis timeout into a
        # permanent 409 that the request path can never clear.
        if collision.unreadable?
          auth_logger.warn '[create-default-workspace] Collision evidence unreadable; failing retryable without latching',
            {
              customer: @customer.extid,
              error: collision.evidence[:error],
              reason: collision.evidence[:reason],
            }
          raise Onetime::AccountProvisioningUnavailable.new(reason: :collision_unreadable, collision: collision)
        end

        if collision.current_valid_workspace?
          existing = collision.organization
          auth_logger.info "[create-default-workspace] Converged on current workspace #{existing.extid} for #{@customer.custid}"
          return existing
        end

        if retry_phantom && collision.classification == :phantom_index &&
           WorkspaceCollision.compare_and_delete(collision)
          auth_logger.warn "[create-default-workspace] Removed phantom contact-email claim and retrying for #{@customer.custid}"
          return create_default_organization(retry_phantom: false)
        end

        @customer.mark_provisioning_failed!(
          code: PROVISIONING_FAILURE_CODE,
          classification: collision.classification,
        )
        auth_logger.warn '[create-default-workspace] Refusing classified contact-email collision',
          {
            customer: @customer.extid,
            classification: collision.classification,
            provisioning_failure_code: PROVISIONING_FAILURE_CODE,
          }
        raise WorkspaceCollision::ProvisioningCollision, collision
      rescue StandardError => ex
        auth_logger.error "[create-default-workspace] Failed to create organization: #{ex.message}"
        raise
      end

      # Detect the verify-disabled federation residual: a federated benefit is
      # about to be claimed for a customer whose email was never verified, in a
      # deployment that has no email-verification step at all. Reaching the claim
      # while unverified means the require_verification gate did not defer us
      # (the gate would have returned early for an unverified customer), so the
      # caller ran with the gate disabled — the standard-signup path does exactly
      # that when verify_account is disabled. See #initialize and
      # #apply_pending_federation! for the full rationale.
      #
      # Never lets audit bookkeeping interfere with the claim itself: any error
      # reading the config is swallowed and treated as "not the residual".
      #
      # @return [Boolean]
      def unverified_immediate_claim?
        return false if @customer&.verified?

        !Onetime.auth_config.verify_account_enabled?
      rescue StandardError
        false
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
      # RESIDUAL (verify_account disabled): when the deployment has no email
      # verification step, the standard-signup caller passes
      # `require_verification: false` and this method claims immediately for a
      # customer whose email ownership was never proven — the benefit-theft
      # surface cannot be closed by deferral there (no verified state ever
      # becomes true, no after_verify_account to re-claim from). We do NOT block
      # the claim (that would disable federation for legitimate verify-disabled
      # deployments); instead {#unverified_immediate_claim?} detects the risky
      # combination and we emit a loud security-audit log so operators can spot
      # abuse. See #initialize.
      #
      # @param org [Onetime::Organization] Newly created organization
      # @return [Boolean] True if pending subscription was applied
      #
      def apply_pending_federation!(org)
        # Creation-policy gate: this caller creates workspaces but does not
        # deliver federated benefits (see #initialize). Checked before the
        # verification gate because it is not a deferral — there is no second
        # chance to re-claim from, and none is wanted. Returning here leaves
        # the PendingFederatedSubscription untouched, which is the whole point.
        unless @claim_pending_federation
          auth_logger.info '[create-default-workspace] Federated subscription claim declined by caller',
            { org: org.extid }
          return false
        end

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

        # A pending record without a resolved planid cannot deliver any
        # benefit. Claiming it anyway would mark the org federated (showing
        # the "subscription synced" notification for a sync that applied
        # nothing) and destroy the only copy of the pending state. Leave the
        # record intact: now that the org exists with an email_hash, the next
        # subscription webhook re-syncs it directly through the federated
        # path, which resolves the plan from subscription metadata.
        if pending.planid.to_s.strip.empty?
          auth_logger.error '[create-default-workspace] Pending federated subscription has no planid; leaving unclaimed',
            {
              org: org.extid,
              hash_prefix: org.email_hash[0..7],
              status: pending.subscription_status,
              region: pending.region,
            }
          return false
        end

        # SECURITY AUDIT (verify-disabled residual): we are about to apply a
        # cross-region subscription benefit. If the customer's email ownership
        # was never proven AND this deployment has no email-verification step at
        # all, this is the residual benefit-theft surface — nothing here can
        # distinguish the real subscriber from an attacker who merely registered
        # the subscriber's email. Do not block (that would silently disable
        # federation for legitimate verify-disabled deployments); emit a loud,
        # structured audit event instead. Verified customers and verify-enabled
        # deployments (where the claim is deferred to after_verify_account) never
        # trip this branch.
        if unverified_immediate_claim?
          auth_logger.warn '[create-default-workspace] SECURITY: federated subscription claimed WITHOUT email verification',
            {
              org: org.extid,
              hash_prefix: org.email_hash[0..7],
              plan: pending.planid,
              reason: 'verify_account disabled: no proof of email ownership at claim time',
            }
        end

        # Apply subscription benefits
        org.subscription_status     = pending.subscription_status
        org.planid                  = pending.planid
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
