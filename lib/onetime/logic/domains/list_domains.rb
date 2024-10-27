require_relative '../base'

module Onetime::Logic
  module Domains
    class ListDomains < OT::Logic::Base
      attr_reader :custom_domains

      def raise_concerns
        limit_action :list_domains
      end

      def process
        OT.ld "[ListDomains] Processing #{cust.custom_domains.length}"
        OT.info "[ListDomains] Processing #{cust.custom_domains.rediskey}"

        @custom_domains = cust.custom_domains_list.map { |cd| cd.safe_dump }
      end

      def success_data
        {
          custid: @cust.custid,
          records: @custom_domains,
          count: @custom_domains.length,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end
    end
  end
end
