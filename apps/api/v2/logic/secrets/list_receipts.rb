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

      # Scopes that can return receipts created by someone other than the
      # caller, and therefore need the capability-token redaction in
      # safe_dump_for. The default (customer) scope reads the caller's own
      # index, so it is deliberately absent: nothing there needs redacting, and
      # leaving it out keeps the personal dashboard byte-identical.
      CROSS_MEMBER_SCOPES = [:org, :domain].freeze
      private_constant :CROSS_MEMBER_SCOPES

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

        # Organization scope returns receipts created by OTHER members — an
        # org-wide audit surface, not a personal one. Gate it at the same
        # admin/owner entitlement the sibling org-wide surface requires
        # (OrganizationAPI::Logic::Organizations::ListSecretActivity calls
        # require_entitlement_in!(org, 'audit_logs')), so the two cannot
        # disagree about who may read the organization's secret activity.
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
        # granting it in ANY plan — so scope=org returns 403 for every role,
        # owners included, until the catalog grants it. That is the same
        # precondition the sibling org-wide surface (ListSecretActivity)
        # already carries, and it fails CLOSED. Grant audit_logs on the plans
        # that should have org-wide visibility, or drop this one line to keep
        # the endpoint at member level — the capability-token redaction in
        # safe_dump_for below is independent of this gate and closes the
        # confidentiality break on its own.
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
        # Cross-member scopes withhold capability tokens on records the caller
        # does not own — see safe_dump_for.
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
        return record unless CROSS_MEMBER_SCOPES.include?(scope)
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

      # Domain scope: receipts created with a specific custom domain
      # Access allowed for any member of the domain's organization
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

        @scope_label = domain.display_domain
        domain.receipts.rangebyscore(since, @now)
      end
    end
  end
end
