# apps/api/account/logic/domains/list_domains.rb

require_relative '../base'

module AccountAPI::Logic
  module Domains
    class ListDomains < AccountAPI::Logic::Base
      attr_reader :custom_domains, :with_brand

      def process_params
        @with_brand = !params[:with_brand].to_s.empty?
      end

      def raise_concerns; end

      def process
        OT.ld "[ListDomains] Processing #{cust.custom_domains.size} #{cust.custom_domains.dbkey}"

        @custom_domains = cust.custom_domains_list.map do |domain|
          domain.safe_dump
        end

        success_data
      end

      def success_data
        {
          user_id: @cust.custid,
          records: @custom_domains,
          count: @custom_domains.length,
          details: {
            cluster: Onetime::Cluster::Features.cluster_safe_dump,
          },
        }
      end
    end
  end
end
