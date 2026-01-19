# apps/api/v2/logic/secrets/list_receipts.rb
#
# frozen_string_literal: true

require 'time'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ListReceipts < V2::Logic::Base
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
        # API access entitlement required for metadata listing
        require_entitlement!('api_access')

        # Validate domain access if domain scope requested
        if (scope == :domain) && !domain_extid
          raise_form_error('Domain extid required for domain scope')
        end
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

        # Get the safe fields for each record using optimized bulk loading
        receipt_objects = Onetime::Receipt.load_multi(query_results).compact
        @records        = receipt_objects.map(&:safe_dump)

        @has_items              = records.any?
        records.sort! { |a, b| b[:updated] <=> a[:updated] }
        @received, @notreceived = *records.partition { |m| m[:is_destroyed] }

        success_data
      end

      def success_data
        {
          'success' => true,
          'custid' => cust.custid,
          'count' => records.count,
          'records' => records,
          'details' => {
            'type' => 'list',
            'scope' => scope&.to_s,
            'scope_label' => scope_label,
            'since' => since,
            'now' => now,
            'has_items' => has_items,
            'received' => received,
            'notreceived' => notreceived,
          },
        }
      end

      private

      # Default scope: receipts owned by the current customer
      def query_customer_receipts
        @scope_label = nil # No label needed for default
        cust.receipts.rangebyscore(since, @now)
      end

      # Organization scope: all receipts created by org members
      def query_organization_receipts
        raise_form_error('No organization context') unless org

        @scope_label = org.display_name
        org.receipts.rangebyscore(since, @now)
      end

      # Domain scope: receipts created with a specific custom domain
      # Access allowed for domain owner or any member of the domain's organization
      def query_domain_receipts
        domain = Onetime::CustomDomain.find_by_extid(domain_extid)
        raise_form_error('Invalid domain') unless domain

        domain_org = domain.organization
        has_access = domain.owner?(cust) || domain_org&.member?(cust)
        raise_form_error('Access denied to domain') unless has_access

        @scope_label = domain.display_domain
        domain.receipts.rangebyscore(since, @now)
      end
    end
  end
end
