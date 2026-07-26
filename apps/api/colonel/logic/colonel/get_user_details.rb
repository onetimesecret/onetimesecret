# apps/api/colonel/logic/colonel/get_user_details.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'

module ColonelAPI
  module Logic
    module Colonel
      class GetUserDetails < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id, :user, :user_secrets, :user_receipts, :organizations, :billing

        # Newest-first page size for the per-owner index reads. The page is what
        # the detail view renders; anything beyond it is reported as truncated
        # rather than silently dropped.
        INDEX_PAGE_SIZE = 100

        # Bounds for the legacy-data fallback SCAN (secrets created before the
        # per-owner index existed). Deliberately bounded by SCAN ROUNDS and
        # WALL CLOCK — never by match count, which is the bug this replaces: a
        # match-count cap on an owner-filtered scan never trips for a normal
        # user, so the loop ran to cursor == '0' over the whole keyspace.
        FALLBACK_SCAN_ROUNDS  = 40
        FALLBACK_SCAN_COUNT   = 500
        FALLBACK_DEADLINE_SEC = 2.0

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) — the latter
          # strips '@' and '.', which silently destroyed the documented email
          # arm below. See AccountIdentifier.
          @user_id = sanitize_account_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid, so every admin surface routes/fetches by it — then email,
          # then objid. Mirrors Auth::Operations::Customers::Show#resolve
          # (show.rb): a plain Customer.load only resolves the internal objid
          # (identifier_field :objid), so an extid would 404.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?
        end

        def process
          # Secrets and receipts are INDEPENDENTLY degradable sections: each is
          # read behind its own rescue so a slow or failing datastore read of
          # one can never stop the identity / plan / role / org / billing
          # read-out from rendering. A support agent needs the record even when
          # the activity lists come back empty.
          @user_secrets  = degrade_on_error('secrets') { collect_secrets }
          @user_receipts = degrade_on_error('receipts') { collect_receipts }

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

        # Run one activity section, degrading to an honest empty-but-truncated
        # result instead of failing the whole page. The rest of the record
        # (identity, plan, role, org, billing) must always render.
        #
        # @return [Hash] `{ items: Array, truncated: Boolean }`
        def degrade_on_error(label)
          yield
        rescue StandardError => ex
          OT.le "[GetUserDetails] #{label} lookup failed: #{ex.class}: #{ex.message}"
          # truncated: true — we know we are NOT showing everything. A silently
          # wrong (empty) list is worse than an honest partial one.
          { items: [], truncated: true }
        end

        # Secrets owned by this user, newest first.
        #
        # PRIMARY PATH: the per-owner index (`customer:<objid>:secrets`), written
        # at the same chokepoint as the `secrets_active` counter
        # (Receipt.spawn_pair → Customer.increment_secrets_active,
        # Secret#destroy! → decrement_secrets_active). One ZREVRANGE plus one
        # pipelined HGETALL batch — O(page), not O(all secrets in the system).
        # This replaces the full-keyspace `secret:*:object` cursor SCAN that
        # loaded every secret one at a time to filter by owner: it was
        # non-blocking for the datastore but unbounded in wall clock for the
        # caller, which is what made this page time out.
        #
        # FALLBACK: secrets created before the index existed are not in it. When
        # the index is empty but the maintained counter says the user owns
        # secrets, fall back to a bounded scan (see #scan_secrets_bounded). A
        # MIXED account (index present but provably incomplete — see
        # #index_incomplete?) pays for the same bounded scan and gets the union
        # (see #merge_secret_sources): without the merge, pre-index secrets were
        # permanently invisible on any account with even one indexed secret,
        # regardless of paging.
        #
        # COUNT CONTRACT (#60, unchanged): `details.secrets.count` equals
        # `items.size` — the detail view renders ITEMS, so the count must match
        # what is on screen and must not be sourced from the up-drifting
        # `secrets_active` counter. `truncated` is how "there may be more" is
        # communicated now, instead of a short list that reads as complete.
        #
        # NOTE for whoever touches the sibling colonel scans: export_usage.rb
        # still has the bug removed here — its `break if secrets.size >= 10_000`
        # counts DATE-RANGE MATCHES, so a narrow range never trips it and the
        # loop walks the whole keyspace one Secret.load at a time. list_secrets.rb
        # uses the same shape but filters nothing, so there every scanned key is a
        # match and the cap does bound it (still 10k un-pipelined loads per page).
        def collect_secrets
          index_size = user.secrets.element_count

          if index_size.zero? && user.secrets_active.to_i.positive?
            # Nothing indexed but the counter says the user owns secrets: this is
            # the pre-index (historical) account. Pay for the bounded scan only
            # here — a user with a live index, or with genuinely zero secrets,
            # never triggers it.
            return scan_secrets_bounded
          end

          indexed = read_secret_index
          return indexed unless index_incomplete?(index_size)

          # MIXED account: the index exists but provably does not cover every
          # secret this user owns (pre-index secrets, or members trimmed off by
          # SECRET_INDEX_LIMIT). Merely flagging `truncated` here left those
          # secrets permanently invisible — no page ever surfaced them. Run the
          # same bounded scan the pre-index account pays for and merge.
          merge_secret_sources(indexed, scan_secrets_bounded)
        end

        # Does the index provably NOT hold every secret this user owns?
        #
        # Compares the index size against the `secrets_active` counter — NOT
        # against the number of items rendered. Both the index and the counter
        # are written at the same two chokepoints and neither is decremented on
        # TTL expiry, so they over-count IDENTICALLY; the difference between them
        # is therefore real missing coverage (secrets created before the index
        # existed, or trimmed off by SECRET_INDEX_LIMIT), never expiry drift.
        #
        # Comparing against the rendered item count instead would fire for
        # every account with an expired secret — and since this predicate now
        # gates the bounded-scan merge (see #collect_secrets), a constantly
        # firing predicate would mean paying the scan on nearly every page.
        def index_incomplete?(index_size)
          user.secrets_active.to_i > index_size
        end

        # Union of the indexed page and the bounded-scan rows for MIXED
        # accounts. The scan re-finds every indexed secret too, so dedupe by
        # secret_id; re-sort newest-first with the same `created.to_f` key the
        # scan path uses (resilient to legacy String `created` values — see
        # #scan_secrets_bounded); slice back to one page. Both inputs are
        # already sliced to INDEX_PAGE_SIZE, which is lossless here: the top
        # page of a union equals the union of each source's top page.
        #
        # `truncated` stays honest for the union: a further indexed page, a
        # capped scan, or an over-full merged page each mean "there may be more
        # than shown". Conversely, when the scan ran to completion un-capped,
        # the union IS every secret that still exists — a counter that outruns
        # it then reflects expired (unshowable) secrets, so the flag clears
        # instead of crying wolf forever.
        def merge_secret_sources(indexed, scanned)
          merged = (indexed[:items] + scanned[:items]).uniq { |row| row[:secret_id] }
          merged.sort_by! { |row| -row[:created].to_f }

          {
            items: merged.first(INDEX_PAGE_SIZE),
            truncated: indexed[:truncated] || scanned[:truncated] || merged.size > INDEX_PAGE_SIZE,
          }
        end

        # Bounded, newest-first read of the per-owner secret index.
        # Members whose object no longer loads (TTL expiry drops the key with no
        # application code running) are simply skipped — the index carries
        # candidates, the object store is the truth.
        def read_secret_index
          # One extra member tells us whether a further page exists.
          objids    = user.secrets.revrange(0, INDEX_PAGE_SIZE)
          truncated = objids.size > INDEX_PAGE_SIZE
          objids    = objids.first(INDEX_PAGE_SIZE)

          items = load_secrets(objids).map { |secret| secret_row(secret) }
          { items: items, truncated: truncated }
        end

        # Legacy-data fallback: cursor SCAN of `secret:*:object`, bounded by SCAN
        # ROUNDS **and** a wall-clock deadline. NOT by match count — an
        # owner-filtered match cap never trips for a normal user, so it bounds
        # nothing. Stopping early sets `truncated`, so the UI can say the list is
        # partial rather than imply it is complete.
        def scan_secrets_bounded
          rows      = []
          cursor    = '0'
          rounds    = 0
          truncated = false
          deadline  = monotonic_now + FALLBACK_DEADLINE_SEC
          dbclient  = Onetime::Secret.dbclient

          loop do
            cursor, keys = dbclient.scan(cursor, match: 'secret:*:object', count: FALLBACK_SCAN_COUNT)
            rounds      += 1

            # Pipeline the object loads: one round trip per SCAN batch instead of
            # one per key (the old code issued a Secret.load per key).
            load_secrets(keys.map { |key| key.split(':')[1] }).each do |secret|
              next unless secret.owner_id.to_s == user.objid.to_s

              rows << secret_row(secret)
            end

            break if cursor == '0'

            if rounds >= FALLBACK_SCAN_ROUNDS || monotonic_now >= deadline
              truncated = true
              break
            end
          end

          # to_f, not `-(created || 0)`: legacy pre-JSON values hydrate as raw
          # Strings (Familia's deserialize_value returns the value as-is on
          # parse failure), and String#-@ is the frozen-string operator — a
          # mixed Float/String batch raised ArgumentError inside sort_by!,
          # which degrade_on_error swallowed into an empty secrets section.
          # nil.to_f == 0.0 covers the missing-value case.
          rows.sort_by! { |row| -row[:created].to_f }
          { items: rows.first(INDEX_PAGE_SIZE), truncated: truncated || rows.size > INDEX_PAGE_SIZE }
        end

        # Receipts owned by this user, newest first, off the per-customer
        # `receipts` sorted set. That index IS populated at every authenticated
        # creation path (`cust.add_receipt` in the v1/v2 secret actions and in
        # create_incoming_secret) and was backfilled for pre-v0.24.5 data by
        # scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb, so there is no
        # scan fallback here — the whole-keyspace `receipt:*:object` walk this
        # replaces is gone, not merely bounded.
        #
        # Receipts minted through Receipt.spawn_pair WITHOUT going through those
        # logic classes (e.g. password-reset / billing-welcome secrets) are not
        # indexed; they are operational artifacts, not customer activity, and
        # were never worth an O(all receipts) walk to surface.
        def collect_receipts
          objids    = user.receipts.revrange(0, INDEX_PAGE_SIZE)
          truncated = objids.size > INDEX_PAGE_SIZE
          objids    = objids.first(INDEX_PAGE_SIZE)

          items = Onetime::Receipt.load_multi(objids.map(&:to_s)).compact.map do |receipt|
            {
              receipt_id: receipt.objid,
              shortid: receipt.shortid,
              state: receipt.state,
              created: receipt.created,
            }
          end

          { items: items, truncated: truncated }
        end

        # Pipelined bulk load (one MULTI/pipeline round trip for the whole
        # batch), dropping ids whose object is gone. load_multi already returns
        # nil for a missing key, so this needs no per-key EXISTS.
        def load_secrets(objids)
          ids = objids.map(&:to_s).reject(&:empty?)
          return [] if ids.empty?

          Onetime::Secret.load_multi(ids).compact
        end

        def secret_row(secret)
          {
            secret_id: secret.objid,
            shortid: secret.shortid,
            state: secret.state,
            created: secret.created,
            expiration: secret.expiration,
          }
        end

        # Monotonic clock: a wall-clock deadline must not be moved by NTP steps.
        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
        #
        # Shape guard: `customer_id` is a stored field (org.stripe_customer_id),
        # not user input, but a corrupt value would make the URL structurally
        # wrong or log-injectable. Stripe customer ids are `cus_` plus
        # alphanumerics; anything else gets no deep link — nil degrades
        # gracefully in both callers (fetch_stripe_billing / stripe_unavailable
        # already carry a nullable dashboard_url).
        def stripe_dashboard_url(customer_id)
          return nil unless customer_id.to_s.match?(/\Acus_[A-Za-z0-9]+\z/)

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
              # count == items.size (the #60 contract: the view renders items,
              # so the number beside the heading must be the number on screen).
              # `truncated` is the honest signal that more may exist beyond this
              # page — a short list that reads as complete is the failure mode
              # this flag exists to prevent.
              secrets: {
                count: user_secrets[:items].size,
                items: user_secrets[:items],
                truncated: user_secrets[:truncated],
              },
              receipts: {
                count: user_receipts[:items].size,
                items: user_receipts[:items],
                truncated: user_receipts[:truncated],
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
