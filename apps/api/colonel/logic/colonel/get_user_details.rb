# apps/api/colonel/logic/colonel/get_user_details.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetUserDetails < ColonelAPI::Logic::Base
        attr_reader :user_id, :user, :user_secrets, :user_receipts, :organizations, :billing

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes/fetches by it — then email,
          # then objid. Mirrors Auth::Operations::Customers::Show#resolve
          # (show.rb): a plain Customer.load only resolves the internal objid
          # (identifier_field :objid), so an extid would 404.
          @user = Onetime::Customer.load_by_extid_or_email(user_id) ||
                  Onetime::Customer.load(user_id)
          raise_not_found('User not found') unless user&.exists?
        end

        def process
          # Get all secrets owned by this user using non-blocking SCAN
          @user_secrets = scan_user_secrets

          # Get all receipts owned by this user using non-blocking SCAN
          @user_receipts = scan_user_receipts

          # Get user's organizations (if they participate in any). The loaded
          # org objects are kept for the billing read-out below (Stripe ids
          # live on Organization, not Customer).
          # organization_instances is the Familia participation reverse accessor
          # (config_name "organization" + "_instances") and returns already-loaded,
          # existence-checked Organization objects. There is NO bare `organizations`
          # method on Customer — the prior `respond_to?(:organizations)` guard was
          # always false, so this block (and the Stripe billing read-out below) was
          # silently dead. See organization_loader.rb for the canonical accessor.
          @organizations = []
          @org_records   = []
          if user.respond_to?(:organization_instances)
            user.organization_instances.to_a.each do |org|
              next unless org&.exists?

              @org_records << org
              @organizations << {
                organization_id: org.objid,
                extid: org.extid,
                display_name: org.display_name,
                is_default: org.is_default,
              }
            end
          end

          # Billing read-out for the "why was I charged" support ticket.
          # Always present; the Stripe block degrades gracefully (billing
          # disabled, no Stripe identity, Stripe unreachable) rather than
          # breaking the detail page — see #build_billing_details.
          @billing = build_billing_details

          success_data
        end

        private

        # Scan secrets owned by user using non-blocking Redis SCAN.
        # O(all secrets) but filters by owner_id. The user.receipts sorted
        # set would be more efficient but isn't populated by spawn_pair yet.
        #
        # SCOPE (#60): this detail view intentionally keeps its own bounded
        # cursor SCAN and does NOT source `details.secrets.count` from the
        # maintained `secrets_active` counter. #60's "count correct beyond 10k"
        # criterion applies to the colonel USERS LIST column (ListUsers), which
        # shows only a count. Here we render the actual secret ITEMS, so the
        # count must equal the items shown (`details.secrets.count == items.size`).
        # Sourcing it from `secrets_active` would surface a visible count/items
        # mismatch because that counter drifts UP between nightly reconciliations
        # (no TTL-expiry decrement — see Customer::Features::CounterFields). This
        # is a bounded, non-blocking cursor SCAN (COUNT=100, 10k cap), so it is
        # CONTRACT-8 compliant — not the blocking KEYS/SMEMBERS the #2211 incident
        # forbids. list_secrets.rb / export_usage.rb keep similar bounded SCANs
        # for the same reason (separate features). Removing the full-keyspace scan
        # via a per-owner secret index is a separate follow-up.
        def scan_user_secrets
          secrets  = []
          cursor   = '0'
          dbclient = Onetime::Secret.dbclient
          pattern  = 'secret:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid  = key.split(':')[1]
              secret = Onetime::Secret.load(objid)
              next unless secret&.exists?
              next unless secret.owner_id == user.objid

              secrets << {
                secret_id: secret.objid,
                shortid: secret.shortid,
                state: secret.state,
                created: secret.created,
                expiration: secret.expiration,
              }
            end

            break if secrets.size >= 10_000
            break if cursor == '0'
          end

          secrets
        end

        # Scan receipts owned by user using non-blocking Redis SCAN.
        def scan_user_receipts
          receipt_list = []
          cursor       = '0'
          dbclient     = Onetime::Receipt.dbclient
          pattern      = 'receipt:*:object'

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)

            keys.each do |key|
              objid   = key.split(':')[1]
              receipt = Onetime::Receipt.load(objid)
              next unless receipt&.exists?
              next unless receipt.owner_id == user.objid

              receipt_list << {
                receipt_id: receipt.objid,
                shortid: receipt.shortid,
                state: receipt.state,
                created: receipt.created,
              }
            end

            break if receipt_list.size >= 10_000
            break if cursor == '0'
          end

          receipt_list
        end

        # Billing summary combining local model state with a live (but
        # optional) Stripe read. Shape:
        #
        #   { enabled:, plan_id:, organization: {...}|nil, stripe: {...} }
        #
        # `plan_id` comes from the billing org (authoritative — Customer#planid
        # is deprecated and drifts), falling back to the legacy Customer field
        # only when the customer participates in no org, so the card renders
        # even when every Stripe path degrades. The organization block is the
        # customer's billing org (Stripe identifiers live on Organization — see
        # WithOrganizationBilling): the first org with a stripe_customer_id,
        # falling back to the default/first org for its local plan fields.
        def build_billing_details
          enabled = Onetime.billing_config.enabled?
          org     = billing_organization

          {
            enabled: enabled,
            plan_id: org&.planid || user.planid,
            organization: org && {
              extid: org.extid,
              display_name: org.display_name,
              planid: org.planid,
              subscription_status: org.subscription_status,
              subscription_period_end: org.subscription_period_end,
            },
            stripe: fetch_stripe_billing(org, enabled),
          }
        end

        def billing_organization
          return nil if @org_records.nil? || @org_records.empty?

          @org_records.find { |org| !org.stripe_customer_id.to_s.empty? } ||
            @org_records.find(&:is_default) ||
            @org_records.first
        end

        # Live Stripe state: current subscription + latest invoice + a deep
        # link to the Stripe dashboard. Mirrors InvestigateOrganization's
        # graceful-degradation contract — `{ available: false, reason: ... }`
        # on every failure path — but rescues StandardError (not just
        # Stripe::StripeError): a Stripe outage, timeout, or API-shape drift
        # must degrade this card, never 500 the customer detail page.
        def fetch_stripe_billing(org, enabled)
          unless enabled && defined?(::Stripe)
            return stripe_unavailable('Billing is not configured')
          end

          customer_id = org&.stripe_customer_id.to_s
          if customer_id.empty?
            return stripe_unavailable('No Stripe customer linked')
          end

          begin
            {
              available: true,
              reason: nil,
              customer_id: customer_id,
              dashboard_url: stripe_dashboard_url(customer_id),
              subscription: fetch_stripe_subscription(org),
              latest_invoice: fetch_latest_invoice(customer_id),
            }
          rescue StandardError => ex
            stripe_unavailable("Stripe unavailable: #{ex.message}", customer_id: customer_id)
          end
        end

        def stripe_unavailable(reason, customer_id: nil)
          {
            available: false,
            reason: reason,
            customer_id: customer_id,
            dashboard_url: customer_id ? stripe_dashboard_url(customer_id) : nil,
            subscription: nil,
            latest_invoice: nil,
          }
        end

        def fetch_stripe_subscription(org)
          subscription_id = org.stripe_subscription_id.to_s
          return nil if subscription_id.empty?

          subscription = ::Stripe::Subscription.retrieve(subscription_id)
          item         = subscription.items.data.first

          {
            id: subscription.id,
            status: subscription.status,
            # current_period_end lives on the subscription item in current
            # Stripe API versions (same accessor InvestigateOrganization uses).
            current_period_end: item&.current_period_end,
          }
        end

        def fetch_latest_invoice(customer_id)
          invoice = ::Stripe::Invoice.list(customer: customer_id, limit: 1).data.first
          return nil unless invoice

          {
            id: invoice.id,
            number: invoice.number,
            status: invoice.status,
            currency: invoice.currency,
            total: invoice.total, # smallest currency unit (e.g. cents)
            created: invoice.created,
            hosted_invoice_url: invoice.hosted_invoice_url,
          }
        end

        # Deep link to this customer in the Stripe dashboard. Keys tell us the
        # mode: test-mode keys need the /test/ path segment.
        def stripe_dashboard_url(customer_id)
          test_mode = Onetime.billing_config.stripe_key.to_s.start_with?('sk_test', 'rk_test')
          "https://dashboard.stripe.com/#{'test/' if test_mode}customers/#{customer_id}"
        end

        def success_data
          {
            record: {
              extid: user.extid,
              # FULL address (colonel-only, scope=internal); obscured client-side
              # and revealed on interaction via RevealEmail.vue.
              email: user.email,
              role: user.role,
              verified: user.verified?,
              suspended: user.suspended?,
              suspended_at: user.suspended_at,
              suspended_by: user.suspended_by,
              suspended_reason: user.suspended_reason,
              created: user.created,
              updated: user.updated,
              last_login: user.last_login,
              planid: user.planid,
              locale: user.locale,
            },
            details: {
              secrets: {
                count: user_secrets.size,
                items: user_secrets,
              },
              receipts: {
                count: user_receipts.size,
                items: user_receipts,
              },
              organizations: organizations,
              billing: billing,
              # Counters are Familia::Counter objects (familia 2.8); coerce
              # to Integer before serialization so JSON's Enumerable path
              # doesn't try to .each over an opaque Counter.
              stats: {
                secrets_created: user.respond_to?(:secrets_created) ? user.secrets_created.to_i : 0,
                secrets_shared: user.respond_to?(:secrets_shared) ? user.secrets_shared.to_i : 0,
                emails_sent: user.respond_to?(:emails_sent) ? user.emails_sent.to_i : 0,
              },
            },
          }
        end
      end
    end
  end
end
