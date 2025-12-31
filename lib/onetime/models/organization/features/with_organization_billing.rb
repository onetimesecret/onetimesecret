# lib/onetime/models/organization/features/with_organization_billing.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Organization Billing Feature
      #
      # Adds Stripe billing fields and methods to Organization model.
      # Organizations own subscriptions, not customers or teams.
      #
      module WithOrganizationBilling
        Familia::Base.add_feature self, :with_organization_billing

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.include InstanceMethods

          # Stripe billing fields
          base.field :stripe_customer_id       # Stripe Customer ID
          base.field :stripe_subscription_id   # Active Stripe Subscription ID
          base.field :planid                   # Plan identifier (e.g., 'single_team_monthly')
          base.field :billing_email            # Billing contact email
          base.field :subscription_status      # active, past_due, canceled, etc.
          base.field :subscription_period_end  # Unix timestamp when current period ends
          base.field :stripe_checkout_email    # Not necessarily the same as billing_email

          # Add indexes. e.g. unique_index :extid, :extid_index, within: Onetime::Organization
          base.unique_index :stripe_customer_id, :stripe_customer_id_index
          base.unique_index :stripe_subscription_id, :stripe_subscription_id_index
          base.unique_index :stripe_checkout_email, :stripe_checkout_email_index
        end

        module InstanceMethods
          # Retrieve Stripe customer object
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def stripe_customer
            return nil if stripe_customer_id.to_s.empty?

            @stripe_customer ||= Stripe::Customer.retrieve(stripe_customer_id)
          rescue Stripe::StripeError => ex
            OT.le "[Organization.stripe_customer] Error: #{ex.message}"
            nil
          end

          # Retrieve Stripe subscription object
          #
          # @return [Stripe::Subscription, nil] Stripe subscription or nil if not found
          def stripe_subscription
            return nil if stripe_subscription_id.to_s.empty?

            @stripe_subscription ||= Stripe::Subscription.retrieve(stripe_subscription_id)
          rescue Stripe::StripeError => ex
            OT.le "[Organization.stripe_subscription] Error: #{ex.message}"
            nil
          end

          # Check if organization has an active subscription
          #
          # @return [Boolean] True if subscription status is 'active' or 'trialing'
          def active_subscription?
            %w[active trialing].include?(subscription_status.to_s)
          end

          # Check if subscription is past due
          #
          # @return [Boolean] True if subscription status is 'past_due'
          def past_due?
            subscription_status.to_s == 'past_due'
          end

          # Check if subscription is canceled
          #
          # @return [Boolean] True if subscription status is 'canceled'
          def canceled?
            subscription_status.to_s == 'canceled'
          end

          # Update billing fields from Stripe subscription
          #
          # Validates subscription data before updating organization fields.
          # Ensures data integrity and prevents corruption from invalid webhook data.
          #
          # @param subscription [Stripe::Subscription] Stripe subscription object
          # @return [Boolean] True if saved successfully
          # @raise [ArgumentError] If subscription is invalid or missing required fields
          def update_from_stripe_subscription(subscription)
            # Validate subscription object type
            unless subscription.is_a?(Stripe::Subscription)
              raise ArgumentError, "Expected Stripe::Subscription, got #{subscription.class}"
            end

            # Validate required fields
            unless subscription.id && subscription.customer && subscription.status
              raise ArgumentError, 'Subscription missing required fields (id, customer, status)'
            end

            # Validate subscription status is known value
            unless Billing::Metadata::VALID_SUBSCRIPTION_STATUSES.include?(subscription.status)
              OT.lw '[Organization.update_from_stripe_subscription] Unknown subscription status', {
                subscription_id: subscription.id,
                status: subscription.status,
                orgid: objid,
              }
            end

            # ==========================================================================
            # REPLAY-SAFE CUSTOMER ID HANDLING
            # ==========================================================================
            # The stripe_customer_id has a unique index. For idempotent replay:
            # - If this org already has this customer ID → continue (same association)
            # - If a different org has this customer ID → error (data integrity issue)
            # - If no org has it yet → proceed with assignment
            # ==========================================================================
            new_customer_id = subscription.customer
            if stripe_customer_id != new_customer_id
              existing_org = Onetime::Organization.find_by_stripe_customer_id(new_customer_id)
              if existing_org && existing_org.objid != objid
                raise OT::Problem, "Stripe customer #{new_customer_id} already linked to org #{existing_org.extid}"
              end
            end

            # Update fields
            self.stripe_subscription_id  = subscription.id
            self.stripe_customer_id      = new_customer_id
            self.subscription_status     = subscription.status
            # current_period_end moved from subscription to subscription items in newer Stripe API
            period_end                   = subscription.items.data.first&.current_period_end
            self.subscription_period_end = period_end.to_s if period_end

            # Extract plan ID with validation
            plan_id     = extract_plan_id_from_subscription(subscription)
            self.planid = plan_id if plan_id

            save
          end

          # Clear billing fields (on subscription cancellation)
          #
          # @return [Boolean] True if saved successfully
          def clear_billing_fields
            self.stripe_subscription_id = nil
            self.subscription_status    = 'canceled'
            self.planid                 = 'free_v1'
            save
          end

          private

          # Extract plan ID from subscription metadata with fallback
          #
          # Tries multiple locations for plan_id in priority order:
          # 1. Subscription metadata['plan_id']
          # 2. First subscription item's price metadata['plan_id']
          # 3. Plan catalog lookup by price_id (for Dashboard/CLI/support changes)
          #
          # The third fallback enables sync when subscriptions are changed outside
          # our checkout flow (e.g., via Stripe Dashboard, CLI, or support).
          #
          # Uses Billing::Metadata constants to avoid magic strings.
          #
          # @param subscription [Stripe::Subscription] Stripe subscription
          # @return [String, nil] Plan ID or nil if not found
          def extract_plan_id_from_subscription(subscription)
            # Load Billing::Metadata for constants
            require_relative '../../../../../apps/web/billing/metadata'

            # Try subscription-level metadata first
            if subscription.metadata && subscription.metadata[Billing::Metadata::FIELD_PLAN_ID]
              return subscription.metadata[Billing::Metadata::FIELD_PLAN_ID]
            end

            # Try price-level metadata
            if subscription.items.data.first&.price&.metadata&.[](Billing::Metadata::FIELD_PLAN_ID)
              return subscription.items.data.first.price.metadata[Billing::Metadata::FIELD_PLAN_ID]
            end

            # Fallback: Resolve plan from price_id via plan catalog
            # This handles subscriptions changed via Stripe Dashboard/CLI/support
            plan_id = resolve_plan_from_price_id(subscription)
            return plan_id if plan_id

            OT.lw '[Organization.extract_plan_id_from_subscription] No plan_id in metadata or catalog', {
              subscription_id: subscription.id,
              orgid: objid,
            }
            nil
          end

          # Resolve plan_id from subscription's price_id via plan catalog
          #
          # Falls back to looking up the plan by matching the subscription's
          # price_id against cached Billing::Plan entries. This enables sync
          # when metadata is missing (e.g., Dashboard changes).
          #
          # @param subscription [Stripe::Subscription] Stripe subscription
          # @return [String, nil] Plan ID or nil if not found
          def resolve_plan_from_price_id(subscription)
            price_id = subscription.items.data.first&.price&.id
            return nil unless price_id

            # Load Billing::Plan for catalog lookup
            require_relative '../../../../../apps/web/billing/models/plan'

            plan = ::Billing::Plan.list_plans.find { |p| p&.stripe_price_id == price_id }

            if plan
              OT.info '[Organization.resolve_plan_from_price_id] Resolved plan from price_id (metadata fallback)', {
                plan_id: plan.plan_id,
                price_id: price_id,
                subscription_id: subscription.id,
                orgid: objid,
              }
              plan.plan_id
            else
              OT.lw '[Organization.resolve_plan_from_price_id] No plan found for price_id', {
                price_id: price_id,
                subscription_id: subscription.id,
                orgid: objid,
              }
              nil
            end
          end

          # Robust Stripe customer retrieval with fallbacks
          #
          # Tries in order:
          # 1. stripe_customer_id (if set) - uses stripe_customer method
          # 2. billing_email lookup
          # 3. stripe_checkout_email lookup
          # 4. contact_email lookup
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def get_stripe_customer
            return stripe_customer if stripe_customer_id.to_s.present?

            get_stripe_customer_by_email
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_customer] Error: #{ex.message}"
            nil
          end

          # Find Stripe customer by email (tries multiple email fields)
          #
          # Attempts to find Stripe customer using organization email fields in priority order:
          # 1. billing_email (primary billing contact)
          # 2. stripe_checkout_email (email used during Stripe checkout)
          # 3. contact_email (general organization contact)
          #
          # @return [Stripe::Customer, nil] Stripe customer or nil if not found
          def get_stripe_customer_by_email
            email_to_try = billing_email.to_s.presence ||
                           stripe_checkout_email.to_s.presence ||
                           contact_email.to_s.presence

            return nil if email_to_try.blank?

            OT.info "[Organization.get_stripe_customer_by_email] Searching for: #{email_to_try}"
            customers = Stripe::Customer.list(email: email_to_try, limit: 1)

            if customers.data.empty?
              OT.info "[Organization.get_stripe_customer_by_email] No customer found: #{email_to_try}"
              nil
            else
              @stripe_customer = customers.data.first
              OT.info "[Organization.get_stripe_customer_by_email] Found: #{@stripe_customer.id}"
              @stripe_customer
            end
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_customer_by_email] Error: #{ex.message}"
            nil
          end

          # Robust subscription retrieval with fallback to listing
          #
          # Tries in order:
          # 1. stripe_subscription_id (if set) - uses stripe_subscription method
          # 2. List active subscriptions for customer and take first
          #
          # Note: Organizations should only have ONE subscription. If multiple subscriptions
          # exist, this returns the first active one found.
          #
          # @return [Stripe::Subscription, nil] Stripe subscription or nil if not found
          def get_stripe_subscription
            return stripe_subscription if stripe_subscription_id.to_s.present?

            # Fallback: Get customer's subscriptions and take first active one
            customer = get_stripe_customer
            return nil unless customer

            OT.info "[Organization.get_stripe_subscription] Listing subscriptions for customer: #{customer.id}"
            subscriptions = Stripe::Subscription.list(
              customer: customer.id,
              status: 'active',
              limit: 1,
            )

            if subscriptions.data.empty?
              OT.info '[Organization.get_stripe_subscription] No active subscriptions found'
              nil
            else
              subscription = subscriptions.data.first
              OT.info "[Organization.get_stripe_subscription] Found subscription: #{subscription.id}"
              subscription
            end
          rescue Stripe::StripeError => ex
            OT.le "[Organization.get_stripe_subscription] Error: #{ex.message}"
            nil
          end
        end
      end
    end
  end
end
