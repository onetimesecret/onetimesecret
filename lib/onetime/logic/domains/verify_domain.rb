require_relative 'get_domain'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class VerifyDomain < GetDomain
      def raise_concerns
        # Run this limiter before calling super which in turn runs
        # the get_domain limiter since verify is a more restrictive. No
        # sense running the get logic more than we need to.
        limit_action :verify_domain

        if OT::Cluster::Features.api_key.to_s.empty?
          OT.le "[VerifyDomain.raise_concerns] Approximated API key not set"
          raise_form_error "Communications error"
        end

        super
      end

      def process
        super

        refresh_vhost
        verify_txt_record
      end

      def refresh_vhost
        api_key = OT::Cluster::Features.api_key

        res = OT::Cluster::Approximated.get_vhost_by_incoming_address(api_key, display_domain)
        if res.code == 200
          payload = res.parsed_response
          OT.info "[VerifyDomain.refresh_vhost] %s" % payload

          custom_domain.vhost = payload['data'].to_json
          custom_domain.updated = OT.now.to_i
          custom_domain.resolving = (payload.dig('data', 'is_resolving') || false).to_s
          custom_domain.save
        else
          msg = payload['message']
          OT.le "[VerifyDomain.refresh_vhost] %s %s [%i]"  % [display_domain, res.code, code]
        end
      end

      def verify_txt_record
        api_key = OT::Cluster::Features.api_key
        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value
        }]
        OT.info "[VerifyDomain.verify_txt_record] %s" % records
        res = OT::Cluster::Approximated.check_records_match_exactly(api_key, records)
        if res.code == 200
          payload = res.parsed_response
          match_records = payload.dig('records')
          found_match = match_records.any? { |record| record['match'] == true }
          OT.info "[VerifyDomain.verify_txt_record] %s (matched:%s)" % [match_records, found_match]

          # Check if any record has match: true
          custom_domain.verified! found_match  # save immediately
        else
          msg = payload['message']
          OT.le "[VerifyDomain.verify_txt_record] %s %s [%i]"  % [display_domain, res.code, msg]
        end
      end
    end
  end
end
