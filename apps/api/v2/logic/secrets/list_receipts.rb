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

      # Only the personal scope skips capability-token redaction. Unlisted
      # scopes fail closed until they are proven to return owner-only records.
      OWN_INDEX_SCOPES = [nil].freeze
      private_constant :OWN_INDEX_SCOPES

      # Scopes that read receipts created by other organization members. Both
      # require the organization-wide audit authorization.
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
        raise_not_found('Not found') unless cust

        require_entitlement!('api_access')

        # The activity flag gates cross-member receipt visibility only.
        if AUDIT_SURFACE_SCOPES.include?(scope) &&
           OT.conf.dig('features', 'organizations', 'audit_logs_enabled').to_s == 'false'
          # Keyword args reach OT.info's **payload and are emitted as
          # SemanticLogger structured payload, not concatenated into the message.
          # The actor is the extid, never custid: custid holds the email address
          # on legacy (pre-v0.22) records, and this line runs on every denial.
          OT.info '[ListReceipts] Authorization denied: audit_logs_enabled feature flag disabled',
            scope: scope.to_s,
            actor: cust&.extid
          raise_form_error('Secret activity is not enabled on this instance', error_type: :forbidden)
        end

        # Cross-member scopes require the organization-wide audit entitlement.
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
        OT.ld '[DEBUG:ListReceipts] Starting query',
          {
            cust_extid: cust&.extid,
            scope: scope,
            domain_extid: domain_extid,
            since: since,
            now: @now,
          }

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

        # Every non-personal scope withholds capability tokens from non-owners.
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

      # Withhold capabilities from receipts the caller does not own. Shortids
      # preserve the required identifier/key shape without granting access.
      def safe_dump_for(receipt)
        record = receipt.safe_dump
        # The personal scope contains only the caller's own receipts.
        return record if OWN_INDEX_SCOPES.include?(scope)
        return record if receipt.owner?(cust)

        shortid = record[:shortid]
        record.merge(
          identifier: shortid,
          key: shortid,
          secret_identifier: nil,
        )
      end

      def query_customer_receipts
        @scope_label = nil
        cust.receipts.rangebyscore(since, @now)
      end

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

      # Domain access and audit authorization are both required.
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

        require_entitlement_in!(domain.primary_organization, 'audit_logs')

        @scope_label = domain.display_domain
        domain.receipts.rangebyscore(since, @now)
      end
    end
  end
end
