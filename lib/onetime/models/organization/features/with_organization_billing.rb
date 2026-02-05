# lib/onetime/models/organization/features/with_organization_billing.rb
#
# frozen_string_literal: true

require 'billing/metadata'
require 'billing/models/plan'
require 'billing/lib/billing_service'
require 'billing/lib/plan_validator'
require 'onetime/utils/email_hash'

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
          base.extend ClassMethods

          # Stripe billing fields
          base.field :stripe_customer_id       # Stripe Customer ID
          base.field :stripe_subscription_id   # Active Stripe Subscription ID
          base.field :planid                   # Plan identifier (e.g., 'single_team_monthly')
          base.field :billing_email            # Billing contact email
          base.field :subscription_status      # active, past_due, canceled, etc.
          base.field :subscription_period_end  # Unix timestamp when current period ends
          base.field :stripe_checkout_email    # Not necessarily the same as billing_email

          # HMAC email hash for cross-region federation (computed from billing_email)
          # Used to match accounts across regions without exposing email addresses.
          # The hash is immutable once set in Stripe customer metadata.
          base.field :email_hash
          base.field :email_hash_synced_at  # Format: YYYY-MM-DD@HH:MMZ

          # Track when subscription was federated (not owned) - for notification UX
          # Unix timestamp, nil if owner or no subscription
          base.field :subscription_federated_at

          # Track when user dismissed the federation notification - for UX
          # Unix timestamp, nil if never dismissed
          base.field :federation_notification_dismissed_at

          # Add indexes. e.g. unique_index :extid, :extid_index, within: Onetime::Organization
          base.unique_index :stripe_customer_id, :stripe_customer_id_index
          base.unique_index :stripe_subscription_id, :stripe_subscription_id_index
          base.unique_index :stripe_checkout_email, :stripe_checkout_email_index
          base.unique_index :billing_email, :billing_email_index
          base.multi_index :email_hash, :email_hash_index
        end

        # Class methods for Organization federation lookups
        module ClassMethods
          # Find organizations with matching email_hash that don't own a subscription
          #
          # "Federated" orgs have the same email as a subscription owner in another region,
          # but don't have their own direct Stripe link (no stripe_customer_id).
          #
          # @param email_hash [String] HMAC hash of email address
          # @return [Array<Onetime::Organization>] Organizations with matching hash and no stripe_customer_id
          #
          # @example
          #   federated = Organization.find_federated_by_email_hash('a1b2c3...')
          #   federated.each { |org| org.update_from_stripe_subscription(sub) }
          #
          def find_federated_by_email_hash(email_hash)
            return [] if email_hash.to_s.empty?

            # Use multi_index to find all orgs with matching hash
            all_matching = find_all_by_email_hash(email_hash)
            return [] unless all_matching

            # Filter to only those without stripe_customer_id (not owners)
            all_matching.select { |org| org.stripe_customer_id.to_s.empty? }
          end
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

          # Federation Methods
          # ------------------
          # These methods support cross-region subscription federation using HMAC email hashes.
          # See: https://github.com/onetimesecret/onetimesecret/issues/2471

          # Compute and store the HMAC email hash from billing_email
          #
          # The hash is computed using FEDERATION_HMAC_SECRET and is deterministic:
          # same email + same secret = same hash across all regions.
          #
          # @return [String, nil] The computed email hash, or nil if billing_email is empty
          # @raise [Onetime::Problem] If FEDERATION_HMAC_SECRET is not configured
          #
          def compute_email_hash!
            self.email_hash           = Onetime::Utils::EmailHash.compute(billing_email)
            self.email_hash_synced_at = Time.now.utc.strftime('%Y-%m-%d@%H:%MZ')
            email_hash
          end

          # Check if this organization owns a subscription (has direct Stripe link)
          #
          # Owners have stripe_customer_id set, meaning they created the subscription.
          # Non-owners receive benefits via federation (matching email_hash).
          #
          # @return [Boolean] True if organization has a stripe_customer_id
          #
          def subscription_owner?
            !stripe_customer_id.to_s.empty?
          end

          # Check if this organization received subscription benefits via federation
          #
          # Federated orgs have subscription_federated_at set but are not owners.
          # This is used to show a one-time notification to users.
          #
          # @return [Boolean] True if subscription was federated (not owned)
          #
          def subscription_federated?
            !subscription_federated_at.to_s.empty? && !subscription_owner?
          end

          # Mark this organization as having received federated subscription benefits
          #
          # Only marks non-owners; owners should never be marked as federated.
          # Uses Unix timestamp for consistency with other timestamp fields.
          #
          # @return [Integer, nil] The timestamp set, or nil if organization is an owner
          #
          def mark_subscription_federated!
            return nil if subscription_owner?

            self.subscription_federated_at = Familia.now.to_i
            subscription_federated_at.to_i
          end

          # Clear the federated status (e.g., when org becomes a direct subscriber)
          #
          # @return [void]
          #
          def clear_federated_status!
            self.subscription_federated_at = nil
          end

          # Check if the federation notification should be shown
          #
          # Shows notification if:
          # - Organization is federated (has subscription_federated_at)
          # - User has NOT dismissed the notification
          #
          # @return [Boolean] True if notification should be shown
          #
          def show_federation_notification?
            subscription_federated? && federation_notification_dismissed_at.to_s.empty?
          end

          # Dismiss the federation notification
          #
          # Records when the user dismissed the notification so it won't show again.
          #
          # @return [Integer] The timestamp when dismissed
          #
          def dismiss_federation_notification!
            self.federation_notification_dismissed_at = Familia.now.to_i
            federation_notification_dismissed_at.to_i
          end

          # Check if federation notification was dismissed
          #
          # @return [Boolean] True if notification was dismissed
          #
          def federation_notification_dismissed?
            !federation_notification_dismissed_at.to_s.empty?
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
              OT.lw '[Organization.update_from_stripe_subscription] Unknown subscription status',
                {
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

          # Extract plan ID from subscription using catalog-first approach (fail-closed)
          #
          # Uses PlanValidator.resolve_plan_id for authoritative catalog lookup.
          # Raises CatalogMissError if price_id is not in catalog - billing integrity
          # is critical, we fail loudly rather than assign incorrect plans.
          #
          # Detects and logs metadata drift for visibility.
          #
          # @param subscription [Stripe::Subscription] Stripe subscription
          # @return [String] Plan ID from catalog
          # @raise [Billing::CatalogMissError] If price_id not in catalog
          # @see Billing::PlanValidator.resolve_plan_id
          def extract_plan_id_from_subscription(subscription)
            price    = subscription.items.data.first&.price
            price_id = price&.id

            raise ArgumentError, 'Subscription has no price' unless price_id

            # Catalog-first resolution (fail-closed)
            plan_id = Billing::PlanValidator.resolve_plan_id(price_id)

            OT.info '[Organization.extract_plan_id_from_subscription] Resolved plan from catalog',
              {
                plan_id: plan_id,
                price_id: price_id,
                subscription_id: subscription.id,
              }

            # Detect and log drift (metadata used only for debugging)
            metadata_plan_id = extract_metadata_plan_id(subscription)
            if metadata_plan_id && metadata_plan_id != plan_id
              OT.lw '[Organization.extract_plan_id_from_subscription] Drift detected - using catalog value',
                {
                  catalog_plan_id: plan_id,
                  metadata_plan_id: metadata_plan_id,
                  subscription_id: subscription.id,
                }
            end

            plan_id
          end

          # Extract plan_id from subscription metadata (for drift detection only)
          #
          # NOT authoritative - catalog is source of truth. This method exists
          # only to detect and log metadata drift for debugging purposes.
          #
          # @param subscription [Stripe::Subscription] Stripe subscription
          # @return [String, nil] Plan ID from metadata or nil
          def extract_metadata_plan_id(subscription)
            price = subscription.items.data.first&.price

            # Check price-level metadata first (defensive: VCR cassettes may have
            # Stripe::StripeObject without metadata method)
            if price.respond_to?(:metadata) && price.metadata
              price_plan_id = price.metadata[Billing::Metadata::FIELD_PLAN_ID]
              return price_plan_id if price_plan_id && !price_plan_id.empty?
            end

            # Fall back to subscription-level metadata
            subscription.metadata&.[](Billing::Metadata::FIELD_PLAN_ID)
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
