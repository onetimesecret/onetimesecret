# apps/web/billing/lib/checkout_target_resolver.rb
#
# frozen_string_literal: true

module Billing
  # Resolves the organization a completed checkout belongs to.
  #
  # Two handlers process the SAME completed checkout and must agree on its
  # target: Billing::Logic::Welcome::ProcessCheckoutSession (the browser
  # redirect to /billing/welcome) and
  # Billing::Operations::WebhookHandlers::CheckoutCompleted (the
  # checkout.session.completed event). They previously carried twin copies of
  # this logic kept in sync by comment, and had silently drifted: the webhook
  # copy was missing both the archived-org filter and the default_org_id
  # priority. That drift was the 2026-08-14 appsec H-2 residue — a member's
  # checkout resolving to a tenant organization they merely belong to. The
  # resolution order lives here so it cannot drift again.
  #
  # Creation policy deliberately does NOT live here: the two handlers differ on
  # what to do when nothing resolves (see each caller's step 4). This module
  # answers "which existing organization is this checkout for", and returns nil
  # when the answer is none.
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
    # Step 1 needs no ownership check — orgid is stamped by the checkout
    # creator (Plans#checkout_redirect, CreateCheckoutLink), each of which
    # authorizes the caller against that org BEFORE the session exists.
    # Re-deriving authority here would be weaker, not stronger: this runs after
    # payment, when roles may have changed.
    #
    # Step 2 is not an ownership question. find_by_stripe_customer_id returns
    # the org that already holds this Stripe customer — the org whose billing
    # relationship the session was bound to. Requiring ownership there would
    # abandon the correct org and mint a duplicate on every replay.
    #
    # Step 3 IS an ownership question, and the only one. It infers the target
    # from memberships, which include organizations the customer merely BELONGS
    # to: JoinDomainOrganization adds a custom-domain SSO caller to the shared
    # tenant org as 'member' and repoints their default_org_id at it. Without
    # the filter, a legacy (orgid-less) checkout resolves to that tenant org and
    # ApplySubscriptionToOrg overwrites its stripe_customer_id, detaching the
    # tenant from its own billing customer. Archived orgs are rejected for the
    # same reason Plans#default_organization_for rejects them: an archived
    # workspace is not a live billing target.
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
    # @param customer [Onetime::Customer]
    # @return [Array<Onetime::Organization>]
    def owned_live_orgs(customer)
      customer.organization_instances.to_a
        .reject(&:archived?)
        .select { |org| owned_by?(org, customer) }
    end

    # True when this organization belongs to the customer as its owner.
    #
    # The membership row is authoritative (Organization#owner? requires an
    # ACTIVE membership with role 'owner'). owner_id is accepted as a secondary
    # signal so a drifted or missing membership row does not make us abandon the
    # customer's own organization and mint a duplicate for a subscription they
    # just paid for — Controllers::Base#load_organization self-heals that same
    # drift. Both live in objid space and are written together at create! (and
    # by Operations::Org::TransferOwnership), and neither can be true for an org
    # owned by someone else, which is the case this filter exists to exclude.
    #
    # @param org [Onetime::Organization]
    # @param customer [Onetime::Customer]
    # @return [Boolean]
    def owned_by?(org, customer)
      org.owner?(customer) || org.owner_id.to_s == customer.objid.to_s
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
    # @param customer [Onetime::Customer]
    # @param logger [#warn] billing logger
    # @param label [String] log prefix identifying the calling surface
    # @return [Onetime::Organization]
    def create_billing_workspace(customer, logger:, label:)
      new_workspace(customer, customer.email)
    rescue Onetime::Problem => ex
      raise unless ex.message.include?('Organization exists')

      logger.warn "#{label} contact_email already reserved, creating workspace without one",
        { customer_extid: customer.extid }
      new_workspace(customer, nil)
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

    # Explicit default_org_id first, then the is_default flag, then any owned
    # live org — the same priority Plans#default_organization_for applies at
    # checkout creation, plus the trailing tolerance the webhook handler has
    # always had. The tolerance is shared deliberately: when one handler
    # accepted an owned org and the other created a fresh one, the same
    # subscription was applied to two organizations, and the second write
    # raised on the unique stripe_customer_id index.
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

    def new_workspace(customer, contact_email)
      Onetime::Organization.create!(
        "#{customer.email}'s Workspace",
        customer,
        contact_email,
        is_default: true,
      )
    end
  end
end
