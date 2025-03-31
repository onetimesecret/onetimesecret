require_relative '../base'

module V2::Logic
  module Domains
    class ListDomains < V2::Logic::Base
      attr_reader :custom_domains, :with_brand

      def process_params
        @with_brand = !params[:with_brand].to_s.empty?
      end

      def raise_concerns
        limit_action :list_domains
      end

      def process
        OT.ld "[ListDomains] Processing #{cust.custom_domains.size}"
          OT.info "[ListDomains] Processing #{cust.custom_domains.rediskey}"

        @custom_domains = cust.custom_domains_list.map do |domain|
          domain.safe_dump
        end
      end

      def success_data
        {
          custid: @cust.custid,
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
