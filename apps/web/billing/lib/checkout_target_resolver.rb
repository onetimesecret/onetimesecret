# apps/web/billing/lib/checkout_target_resolver.rb
#
# frozen_string_literal: true

module Billing
  # Resolves the organization a completed checkout belongs to.
  #
  # The resolution order lives here so every completion path uses the same
  # target-selection policy.
  #
  # This module answers "which existing organization is this checkout for" and
  # returns nil when none resolves; callers own their creation policy.
  module CheckoutTargetResolver
    extend self

    # Resolve the target organization from an already-authorized checkout.
    #
    # Priority:
    # 1. orgid from subscription metadata (explicit org that initiated checkout)
    # 2. Org already linked to this Stripe customer (idempotent replay)
    # 3. Customer's own, live org (legacy/fallback — ownership required)
    #
    # AUTHORIZATION, and why it applies at step 3 only:
    #
    # Step 1 needs no ownership check: it uses the checkout's explicit target.
    # Re-deriving authority after payment would be weaker, not stronger, because
    # roles may have changed.
    #
    # Step 2 is not an ownership question: it recovers the organization already
    # bound to the session's Stripe customer. Requiring ownership would abandon
    # that target and mint a duplicate on replay.
    #
    # Step 3 IS an ownership question, and the only one. It infers a target
    # from memberships, which can include organizations the customer does not
    # own. Without the filter, a legacy checkout can overwrite another
    # organization's Stripe customer. Archived organizations are not live
    # billing targets.
    #
    # @param customer [Onetime::Customer] customer named by the subscription
    # @param metadata [Stripe::StripeObject, Hash] subscription metadata
    # @param stripe_customer_id [String, nil] the session's Stripe customer
    # @param logger [#info, #warn] billing logger
    # @param label [String] log prefix identifying the calling surface
    # @return [Onetime::Organization, nil] nil when nothing resolves — the
    #   caller decides what to create (their step 4)
    def resolve(customer:, metadata:, stripe_customer_id:, logger:, label:)
      from_metadata(metadata, logger, label) ||
        from_stripe_customer(stripe_customer_id, logger, label) ||
        from_owned_orgs(customer, logger, label)
    end

    # The customer's live organizations that they own, in membership order.
    #
    # Ownership is the ACTIVE 'owner' membership row (Organization#owner?),
    # the sole authority per ADR-012; the deprecated owner_id field is
    # deliberately not consulted. When the two disagree there is no way to
    # know which is right, so this predicate takes the recoverable branch:
    # fall through to the caller's create path (a spurious workspace) rather
    # than resolve to an org the customer may no longer own.
    #
    # @param customer [Onetime::Customer]
    # @return [Array<Onetime::Organization>]
    def owned_live_orgs(customer)
      customer.organization_instances.to_a
        .reject(&:archived?)
        .select { |org| org.owner?(customer) }
    end

    # Create the organization a checkout's subscription will land on.
    #
    # Organization.create! reserves contact_email in a unique index, and an
    # ARCHIVED organization still holds its reservation. That is precisely the
    # caller who gets here (their own orgs are archived, so resolve returned
    # nil), so passing the customer email would raise 'Organization exists for
    # that email address' and abandon a paid subscription. Retry without a
    # contact_email: it is not the billing address of record — billing_email /
    # stripe_customer_id are, and update_from_stripe_subscription sets those
    # moments later.
    #
    # The workspace is born holding the stripe_customer_id claim so two
    # surfaces completing the SAME checkout cannot both create one; see
    # {.adopt_claimed_workspace}.
    #
    # @param customer [Onetime::Customer]
    # @param logger [#warn] billing logger
    # @param label [String] log prefix identifying the calling surface
    # @param stripe_customer_id [String, nil] the checkout's Stripe customer
    # @return [Onetime::Organization]
    def create_billing_workspace(customer, logger:, label:, stripe_customer_id: nil)
      begin
        new_workspace(customer, customer.email, stripe_customer_id)
      rescue Onetime::OrganizationExists
        logger.warn "#{label} contact_email already reserved, creating workspace without one",
          { customer_extid: customer.extid }
        new_workspace(customer, nil, stripe_customer_id)
      end
    rescue Familia::RecordExistsError => ex
      adopt_claimed_workspace(ex, logger: logger, label: label)
    end

    # Adopt the workspace that won the stripe_customer_id claim.
    #
    # The checkout's Stripe customer is the only identifier both completion
    # surfaces hold BEFORE either of them writes, and its unique index claim
    # is a server-side CAS — so it elects one creator without a lock. Losing
    # the claim means the other surface already created this checkout's
    # workspace: adopt it rather than mint a duplicate.
    #
    # @param error [Familia::RecordExistsError] raised by the losing create
    # @param logger [#warn] billing logger
    # @param label [String] log prefix identifying the calling surface
    # @return [Onetime::Organization]
    # @raise [Onetime::Problem] when the winner cannot be loaded — the caller
    #   must fail loudly (and, on the webhook, be retried) rather than fall
    #   through to a second create.
    def adopt_claimed_workspace(error, logger:, label:)
      winner = error.existing_id && Onetime::Organization.load(error.existing_id)
      unless winner
        raise Onetime::Problem,
          "#{label} lost the stripe_customer_id claim to #{error.existing_id.inspect}, which could not be loaded"
      end

      logger.warn "#{label} adopting workspace created concurrently for this checkout",
        { orgid: winner.objid, extid: winner.extid }
      winner
    end

    private

    def from_metadata(metadata, logger, label)
      orgid = metadata['orgid']
      return nil unless orgid

      org = Onetime::Organization.load(orgid)
      if org
        logger.info "#{label} Found org from subscription metadata",
          { orgid: orgid, extid: org.extid }
        return org
      end

      logger.warn "#{label} orgid in metadata not found", { orgid: orgid }
      nil
    end

    def from_stripe_customer(stripe_customer_id, logger, label)
      return nil unless stripe_customer_id.is_a?(String)
      return nil unless stripe_customer_id.start_with?('cus_')

      org = Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)
      return nil unless org

      logger.info "#{label} Found org by stripe_customer_id",
        { stripe_customer_id: stripe_customer_id, extid: org.extid }
      org
    end

    # Prefer the explicit default, then the default-marked organization, then
    # any owned live organization.
    def from_owned_orgs(customer, logger, label)
      owned = owned_live_orgs(customer)

      if customer.default_org_id.to_s.length.positive?
        explicit = owned.find { |org| org.objid == customer.default_org_id }
        if explicit
          logger.info "#{label} Using customer default_org_id (fallback)", { extid: explicit.extid }
          return explicit
        end
      end

      org = owned.find(&:is_default) || owned.first
      return nil unless org

      logger.info "#{label} Using customer default org (fallback)", { extid: org.extid }
      org
    end

    def new_workspace(customer, contact_email, stripe_customer_id)
      Onetime::Organization.create!(
        "#{customer.email}'s Workspace",
        customer,
        contact_email,
        is_default: true,
        **Onetime::Organization.stripe_claim_fields(stripe_customer_id),
      )
    end
  end
end
