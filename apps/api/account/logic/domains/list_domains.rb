# apps/api/account/logic/domains/list_domains.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI::Logic
  module Domains
    class ListDomains < AccountAPI::Logic::Base
      attr_reader :custom_domains, :with_brand

      def process_params
        @with_brand = !params['with_brand'].to_s.empty?
      end

      def raise_concerns
        require_organization!
      end

      def process
        domains = organization.list_domains

        OT.ld "[ListDomains] Processing #{domains.size} domains for org #{organization.objid}"

        @custom_domains = domains.map do |domain|
          domain.safe_dump
        end

        success_data
      end

      def success_data
        {
          user_id: @cust.objid,
          organization: organization.safe_dump,
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
