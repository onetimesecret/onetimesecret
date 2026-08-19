# apps/api/v2/logic/secrets/list_receipts.rb
#
# frozen_string_literal: true

require 'time'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # List Receipts
    #
    # @api Lists receipts (metadata records) for secrets created within the
    #   last 30 days. Supports scoping by customer (default), organization,
    #   or custom domain. Returns each receipt's state, timestamps, and
    #   summary information.
    class ListReceipts < V2::Logic::Base
      SCHEMAS = { response: 'receiptList' }.freeze

      # Scopes EXEMPT from the capability-token redaction in safe_dump_for.
      # Only the default (customer) scope qualifies: it reads the caller's own
      # index (cust.receipts), so every record in it is already the caller's,
      # nothing needs redacting, and the personal dashboard response stays
      # byte-identical.
      #
      # Deliberately an exemption list rather than a list of cross-member
      # scopes. An allowlist of scopes-that-redact fails OPEN: the first scope
      # added to the #process case statement and not to the list would emit
      # full capability tokens again and silently reopen appsec finding H-1.
      # Inverted, an unlisted scope fails CLOSED — it withholds tokens for
      # records the caller does not own until someone proves the scope reads an
      # owner-only index and adds it here.
      OWN_INDEX_SCOPES = [nil].freeze
      private_constant :OWN_INDEX_SCOPES

      # Scopes that read an organization's receipts, including those created by
      # OTHER members. Both are the organization's audit surface, so both carry
      # the org-wide authorization bar (instance flag + audit_logs entitlement)
      # rather than the member-level one — see raise_concerns for the flag and
      # query_domain_receipts for the domain-scoped entitlement.
      AUDIT_SURFACE_SCOPES = [:org, :domain].freeze
      private_constant :AUDIT_SURFACE_SCOPES

      attr_reader :records,
        :since,
        :now,
        :query_results,
        :received,
        :notreceived,
        :has_items,
        :scope,
        :domain_extid,
        :scope_label

      def process_params
        # Calculate the timestamp for 30 days ago
        @now   = Familia.now
        @since = (Familia.now - 30.days).to_i

        # Scope parameter: nil (default customer), 'org', or 'domain'
        @scope        = params['scope']&.to_sym
        @domain_extid = params['domain_extid']
      end

      def raise_concerns
        # Receipts require an authenticated customer
        raise_not_found('Not found') unless cust

        # API access entitlement required for metadata listing.
        # Applies to every scope, including the default (own receipts) one.
        require_entitlement!('api_access')

        # Instance-level exclusion, mirroring the sibling org-wide surface:
        # a self-hosted operator can remove the org's activity/receipt trail
        # from the product with ORGS_AUDIT_LOGS_ENABLED=false. Default-true
        # contract — only an explicit false disables; a missing key (older
        # config file) counts as enabled. Compared on the string form, same as
        # ConfigSerializer#build_feature_flags and ListSecretActivity, so a
        # hand-edited config yielding the string 'false' darkens BOTH surfaces
        # rather than leaving this one serving the stream while the UI hides
        # the tab.
        #
        # Applies to scope=org AND scope=domain: both return other members'
        # receipts. Gates exposure only — receipt collection is unaffected, as
        # is the caller's own (default-scope) list.
        if AUDIT_SURFACE_SCOPES.include?(scope) &&
           OT.conf.dig('features', 'organizations', 'audit_logs_enabled').to_s == 'false'
          # Keyword args reach OT.info's **payload and are emitted as
          # SemanticLogger structured payload, not concatenated into the message.
          OT.info '[ListReceipts] Authorization denied: audit_logs_enabled feature flag disabled',
            scope: scope.to_s,
            actor: cust&.custid
          raise_form_error('Secret activity is not enabled on this instance', error_type: :forbidden)
        end

        # Organization scope returns receipts created by OTHER members — an
        # org-wide audit surface, not a personal one. Gate it at the same
        # admin/owner entitlement the sibling org-wide surface requires
        # (OrganizationAPI::Logic::Organizations::ListSecretActivity calls
        # require_entitlement_in!(org, 'audit_logs')), so the two cannot
        # disagree about who may read the organization's secret activity.
        # scope=domain clears the same bar against the domain's OWNING
        # organization — see query_domain_receipts, which is where the domain
        # is resolved.
        #
        # Effective entitlements are the org plan ∩ ROLE_ENTITLEMENTS[role],
        # and audit_logs is an ADMIN_ENTITLEMENTS member
        # (lib/onetime/models/organization_membership.rb), so this admits
        # admins and owners of orgs whose plan includes audit logs.
        #
        # ⚠️ OPERATOR ACTION on billing-enabled deployments. Standalone /
        # billing-disabled installs are unaffected — STANDALONE_ENTITLEMENTS
        # (organization/features/with_plan_entitlements.rb) already includes
        # audit_logs. But when billing is ON, entitlements come from the plan
        # catalog, and the shipped example catalog
        # (etc/examples/billing.example.yaml) defines audit_logs without
        # granting it in ANY plan — so scope=org and scope=domain return 403
        # for every role, owners included, until the catalog grants it. That is
        # the same precondition the sibling org-wide surface
        # (ListSecretActivity) already carries, and it fails CLOSED. Grant
        # audit_logs on the plans that should have org-wide visibility, or drop
        # this line and its twin in query_domain_receipts to keep the endpoint
        # at member level — the capability-token redaction in safe_dump_for
        # below is independent of these gates and closes the confidentiality
        # break on its own.
        require_entitlement!('audit_logs') if scope == :org

        # Validate domain access if domain scope requested
        return unless (scope == :domain) && !domain_extid

        raise_form_error(
          I18n.t(
            'web.secrets.errors.domain_extid_required',
            locale: locale,
            default: 'Domain extid required for domain scope',
          ),
        )
      end

      def process
        # Debug logging for receipt list investigation (only in debug mode)
        OT.ld '[DEBUG:ListReceipts] Starting query',
          {
            cust_id: cust&.custid,
            cust_objid: cust&.objid,
            scope: scope,
            domain_extid: domain_extid,
            since: since,
            now: @now,
          }

        # Query based on scope
        @query_results = case scope
                         when :org
                           query_organization_receipts
                         when :domain
                           query_domain_receipts
                         else
                           query_customer_receipts
                         end

        OT.ld '[DEBUG:ListReceipts] Query results',
          {
            query_count: query_results.size,
            first_3_results: query_results.first(3),
          }

        # Get the safe fields for each record using optimized bulk loading.
        # Every scope but the default one withholds capability tokens on
        # records the caller does not own — see safe_dump_for.
        receipt_objects = Onetime::Receipt.load_multi(query_results).compact
        @records        = receipt_objects.map { |receipt| safe_dump_for(receipt) }

        @has_items              = records.any?
        records.sort! { |a, b| b[:updated] <=> a[:updated] }
        @received, @notreceived = *records.partition { |m| m[:is_destroyed] }

        success_data
      end

      def success_data
        {
          'success' => true,
          'custid' => cust&.custid,
          'count' => records.count,
          'records' => records,
          'details' => {
            'type' => 'list',
            'scope' => scope&.to_s,
            'scope_label' => scope_label,
            'since' => since,
            'now' => now,
            'has_items' => has_items,
            'revealed_receipts' => received,
            'pending_receipts' => notreceived,
          },
        }
      end

      private

      # Serialize one receipt, withholding capability tokens when the caller is
      # not its owner.
      #
      # In this product an identifier IS the capability. `secret_identifier` is
      # sufficient to reveal the secret — the reveal path performs no ownership
      # check by design, the identifier is the authorization — and the receipt
      # `identifier`/`key` authorize managing it, including burn. The org- and
      # domain-scoped listings return other members' receipts, so emitting
      # those fields handed every caller a live capability for every
      # colleague's unread secret.
      #
      # Redaction is the DEFAULT, not an opt-in for named scopes: only the
      # scopes on OWN_INDEX_SCOPES skip it, and any scope added to #process
      # later inherits the withholding rather than the leak.
      #
      # Shortids are this product's established safe form for cross-member
      # surfaces: ListSecretActivity emits "receipt/secret shortids only —
      # never full identifiers, which are capability tokens". We follow it.
      # identifier/key collapse to the receipt shortid, which is already
      # emitted unconditionally in its own `shortid` field (so this adds no
      # exposure) and cannot be used to reveal or burn anything;
      # secret_identifier is nulled.
      #
      # Why shortid rather than nil or '': the V3 contract types identifier and
      # key as required, non-nullable strings (src/schemas/contracts/receipt.ts)
      # inside a strict array, so a null would fail that record and blank the
      # entire response; '' would parse but defeats the `??` fallbacks on the
      # client and is identical across rows. secret_identifier is nullish in the
      # same contract, so null is the correct withheld value there.
      def safe_dump_for(receipt)
        record = receipt.safe_dump
        # Narrow exemption (see OWN_INDEX_SCOPES): the default scope reads the
        # caller's own index, so this returns the dump untouched — and without
        # a per-record owner? call — keeping the personal dashboard response
        # byte-identical. Every other scope falls through to the ownership
        # test below.
        return record if OWN_INDEX_SCOPES.include?(scope)
        return record if receipt.owner?(cust)

        shortid = record[:shortid]
        record.merge(
          identifier: shortid,
          key: shortid,
          secret_identifier: nil,
        )
      end

      # Default scope: receipts owned by the current customer
      def query_customer_receipts
        @scope_label = nil # No label needed for default
        cust.receipts.rangebyscore(since, @now)
      end

      # Organization scope: all receipts created by org members
      def query_organization_receipts
        unless auth_org
          raise_form_error(
            I18n.t(
              'web.secrets.errors.no_organization_context',
              locale: locale,
              default: 'No organization context',
            ),
          )
        end

        @scope_label = auth_org.display_name
        auth_org.receipts.rangebyscore(since, @now)
      end

      # Domain scope: receipts created with a specific custom domain.
      #
      # Two gates, both required. Membership in the domain's organization
      # (accessible_by?) says the caller may see this domain at all; the
      # audit_logs entitlement says they may read OTHER members' receipts
      # through it. Without the second, a `member` correctly refused scope=org
      # simply re-runs the query as
      # scope=domain&domain_extid=<one of the org's domains> and receives every
      # colleague's domain-bound receipt metadata — the entitlement boundary
      # bypass in the appsec review (M-6).
      #
      # The entitlement is evaluated in the DOMAIN's organization
      # (require_entitlement_in!) rather than the caller's auth_org
      # (require_entitlement!): the two diverge for a caller who belongs to
      # several organizations, and the records being read belong to the
      # domain's org, so that is the org whose plan ∩ role must grant it.
      def query_domain_receipts
        domain = Onetime::CustomDomain.find_by_extid(domain_extid)
        unless domain
          raise_form_error(
            I18n.t(
              'web.secrets.errors.invalid_domain',
              locale: locale,
              default: 'Invalid domain',
            ),
          )
        end

        has_access = domain.accessible_by?(cust)
        unless has_access
          raise_form_error(
            I18n.t(
              'web.secrets.errors.access_denied_to_domain',
              locale: locale,
              default: 'Access denied to domain',
            ),
          )
        end

        # primary_organization resolves the domain's org_id to the record.
        # It cannot be nil past accessible_by?, which returns false when
        # org_id is blank or the organization no longer loads; and
        # require_entitlement_in! fails closed (Problem) on nil regardless.
        require_entitlement_in!(domain.primary_organization, 'audit_logs')

        @scope_label = domain.display_domain
        domain.receipts.rangebyscore(since, @now)
      end
    end
  end
end
