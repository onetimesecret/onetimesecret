# apps/api/v2/logic/domains/verify_domain.rb

require 'onetime/cluster'
require_relative 'get_domain'

module V2::Logic
  module Domains
    class VerifyDomain < GetDomain
      def raise_concerns
        if Onetime::Cluster::Features.api_key.to_s.empty?
          OT.le '[VerifyDomain.raise_concerns] Approximated API key not set'
          raise_form_error 'Communications error'
        end

        super
      end

      def process
        super

        refresh_vhost
        refresh_txt_record_status
      end

      def refresh_vhost
        api_key = Onetime::Cluster::Features.api_key

        res = Onetime::Cluster::Approximated.get_vhost_by_incoming_address(api_key, display_domain)
        if res.code == 200
          payload = res.parsed_response
          OT.info '[VerifyDomain.refresh_vhost] %s' % payload

          custom_domain.vhost = payload['data'].to_json
          custom_domain.updated = OT.now.to_i
          custom_domain.resolving = (payload.dig('data', 'is_resolving') || false).to_s
          custom_domain.save
        else
          msg = payload['message']
          OT.le format('[VerifyDomain.refresh_vhost] %s %s [%i]: %s', display_domain, res.code, code, msg)
        end
      end

      def refresh_txt_record_status
        api_key = Onetime::Cluster::Features.api_key
        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value,
        }]
        OT.info '[VerifyDomain.refresh_txt_record_status] %s' % records
        res = Onetime::Cluster::Approximated.check_records_match_exactly(api_key, records)
        if res.code == 200
          payload = res.parsed_response
          match_records = payload['records']
          found_match = match_records.any? { |record| record['match'] == true }
          OT.info format('[VerifyDomain.refresh_txt_record_status] %s (matched:%s)', match_records, found_match)

          # Check if any record has match: true
          custom_domain.verified! found_match # save immediately
        else
          payload = res.parsed_response
          msg = payload['message'] || 'Inknown error'
          OT.le format('[VerifyDomain.refresh_txt_record_status] %s %s [%i]', display_domain, res.code, msg)
        end
      end
    end
  end
end
