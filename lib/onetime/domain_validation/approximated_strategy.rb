# lib/onetime/domain_validation/approximated_strategy.rb
#
# frozen_string_literal: true

require_relative 'features'
require_relative 'approximated_client'
require_relative 'txt_verifier'

module Onetime
  module DomainValidation
    # ApproximatedStrategy - Uses approximated.app API for validation and certs.
    #
    # Design Decision: Dependency injection for the API client.
    #
    # The client is injected at construction, defaulting to ApproximatedClient.
    # This enables:
    # - Unit testing with mock clients
    # - Easy swapping of HTTP implementations
    # - Clear separation between strategy logic and HTTP transport
    #
    # Configuration is read from DomainValidation::Features.
    #
    # The #check_status method returns a vhost Hash stored on CustomDomain:
    #
    #   {
    #     "ready": true,
    #     "has_ssl": true,
    #     "is_resolving": true,
    #     "status": "ACTIVE_SSL",
    #     "status_message": "Human-readable status",
    #     "data": {}
    #   }
    #
    class ApproximatedStrategy < BaseStrategy
      # Vhost statuses that mean "serving over SSL with no known issues".
      # ACTIVE_SSL_PROXIED is the normal state for a host fronted by another
      # proxy (e.g. a Cloudflare CNAME setup): DNS points elsewhere but
      # requests reach the cluster and the certificate is active.
      ACTIVE_SSL_STATUSES = %w[ACTIVE_SSL ACTIVE_SSL_PROXIED].freeze

      # Seconds between domains in a bulk run, to stay under the API rate cap.
      BULK_RATE_LIMIT = 0.5

      attr_reader :client, :config, :txt_verifier

      # @param config [Hash] Application configuration (typically OT.conf)
      # @param client [Module] HTTP client module (default: ApproximatedClient)
      # @param txt_verifier [#verify] Native TXT check used when the upstream
      #   checker is indeterminate (default: TxtVerifier). Injected so specs
      #   never touch the network.
      #
      def initialize(config, client: ApproximatedClient, txt_verifier: TxtVerifier.new)
        @config       = config
        @client       = client
        @txt_verifier = txt_verifier
      end

      # Validates domain ownership via TXT record.
      #
      # Approximated's checker is asked first. Whenever it gives no answer
      # about the customer's DNS our own lookup (TxtVerifier) decides, see
      # #classify_ownership. That covers a 200 whose lookup failed and also
      # the cases where the checker could not be asked at all: no API key, a
      # non-200 response, a client exception. None of those says anything
      # about the TXT record, so none of them is reported as a failed check.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def validate_ownership(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          return upstream_unavailable(custom_domain, 'Approximated API key not configured')
        end

        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value,
        }]

        res = client.check_records_match_exactly(api_key, records)

        if res.code == 200
          payload       = res.parsed_response
          match_records = Array(payload['records'])

          classify_ownership(custom_domain, match_records)
        else
          upstream_unavailable(custom_domain, "Validation check failed: #{res.code}", error: res.parsed_response)
        end
      rescue StandardError => ex
        OT.le "[ApproximatedStrategy] Error validating #{custom_domain.display_domain}: #{ex.message}"
        upstream_unavailable(custom_domain, "Error: #{ex.message}")
      end

      # Requests SSL certificate by creating a vhost.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#request_certificate
      #
      def request_certificate(custom_domain)
        api_key      = Features.api_key
        vhost_target = Features.vhost_target

        OT.ld "[ApproximatedStrategy.request_certificate] domain=#{custom_domain.display_domain} " \
              "vhost_target=#{vhost_target.inspect} api_key_present=#{!api_key.to_s.empty?}"

        if api_key.to_s.empty?
          return { status: 'error', message: 'Approximated API key not configured' }
        end

        if vhost_target.to_s.empty?
          OT.le '[ApproximatedStrategy] vhost_target not configured (set features.domains.approximated.vhost_target)'
          return { status: 'error', message: 'Approximated vhost_target not configured' }
        end

        OT.ld '[ApproximatedStrategy.request_certificate] Creating vhost: ' \
              "incoming=#{custom_domain.display_domain} target=#{vhost_target} port=443"

        res = client.create_vhost(
          api_key,
          custom_domain.display_domain,
          vhost_target,
          '443',
        )

        # 200 = existing vhost returned, 201 = new vhost created
        if [200, 201].include?(res.code)
          payload = res.parsed_response
          {
            status: 'requested',
            message: 'Virtual host created',
            data: payload['data'],
          }
        else
          {
            status: 'error',
            message: "Failed to create vhost: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy] Error requesting cert for #{custom_domain.display_domain}: #{ex.message}"
        { status: 'error', message: "Error: #{ex.message}" }
      end

      # Checks current domain status from Approximated.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#check_status
      #
      def check_status(custom_domain)
        api_key = Features.api_key

        OT.ld "[ApproximatedStrategy.check_status] domain=#{custom_domain.display_domain} " \
              "api_key_present=#{!api_key.to_s.empty?}"

        if api_key.to_s.empty?
          return { ready: false, message: 'Approximated API key not configured' }
        end

        res = client.get_vhost_by_incoming_address(
          api_key,
          custom_domain.display_domain,
        )

        if res.code == 200
          payload = res.parsed_response
          data    = payload['data']

          # UNKNOWN is Approximated's "cannot determine a reliable status right
          # now" — not evidence that DNS stopped resolving. Report nil so
          # VerifyDomain leaves the stored resolving flag alone, the same
          # discipline as an indeterminate TXT check.
          indeterminate = data['status'] == 'UNKNOWN'

          {
            ready: ACTIVE_SSL_STATUSES.include?(data['status']),
            has_ssl: data['has_ssl'],
            is_resolving: indeterminate ? nil : data['is_resolving'],
            status: data['status'],
            status_message: data['status_message'],
            data: data,
          }
        else
          {
            ready: false,
            message: "Status check failed: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy] Error checking status for #{custom_domain.display_domain}: #{ex.message}"
        { ready: false, message: "Error: #{ex.message}" }
      end

      # Deletes the vhost from Approximated.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#delete_vhost
      #
      def delete_vhost(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          OT.info '[ApproximatedStrategy.delete_vhost] API key not configured'
          return { deleted: false, message: 'Approximated API key not configured' }
        end

        res = client.delete_vhost(api_key, custom_domain.display_domain)

        if res.success?
          payload = res.parsed_response
          OT.info "[ApproximatedStrategy.delete_vhost] Deleted #{custom_domain.display_domain}"
          {
            deleted: true,
            message: "Deleted vhost: #{custom_domain.display_domain}",
            data: payload,
          }
        else
          OT.le "[ApproximatedStrategy.delete_vhost] Failed: #{res.code} for #{custom_domain.display_domain}"
          { deleted: false, message: "Failed to delete vhost: status #{res.code}" }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy.delete_vhost] Error: #{custom_domain.display_domain} - #{ex.message}"
        { deleted: false, message: "Error: #{ex.message}" }
      end

      # Retrieves DNS widget token from Approximated.
      #
      # @return [Hash] See BaseStrategy#get_dns_widget_token
      #
      def get_dns_widget_token
        api_key = Features.api_key

        if api_key.to_s.empty?
          return { available: false, message: 'Approximated API key not configured' }
        end

        res = client.get_dns_widget_token(api_key)

        if res.code == 200
          {
            available: true,
            token: res.parsed_response['token'],
            api_url: 'https://cloud.approximated.app/api/dns',
            expires_in: 600, # 10 minutes
          }
        else
          {
            available: false,
            message: "Failed to get token: #{res.code}",
          }
        end
      rescue HTTParty::ResponseError => ex
        OT.le "[ApproximatedStrategy.get_dns_widget_token] Error: #{ex.message}"
        { available: false, message: "Error: #{ex.message}" }
      end

      # @return [Boolean] true - Approximated supports the DNS widget
      def supports_dns_widget?
        true
      end

      # @return [Boolean] true - Approximated actively manages certificates
      def manages_certificates?
        true
      end

      # @return [Boolean] true - a pass means the TXT record was checked, by
      #   Approximated's API or our own lookup
      def proves_ownership?
        true
      end

      # Approximated caps API requests; each domain in a bulk run costs two
      # calls (check_records + get_vhost_by_incoming_address).
      def bulk_rate_limit
        BULK_RATE_LIMIT
      end

      private

      # Classifies a check-records-match-exactly response into three outcomes.
      #
      # Approximated's contract for 'actual_values' is an Array of the values
      # it saw, or the literal `false` "when DNS resolution or the record-type
      # lookup failed". Only an Array is evidence about the customer's DNS:
      #
      #   match == true            -> validated: true
      #   actual_values is Array   -> validated: false (not found / mismatch)
      #   anything else            -> upstream indeterminate; ask TxtVerifier
      #
      # The native lookup can establish ownership and can fail closed for a
      # domain that has never been verified. It cannot, by itself, revoke an
      # existing verification while the independent upstream checker has no
      # answer: split-horizon DNS, filtering, or a stale negative cache could
      # make one local resolver return NXDOMAIN for a valid public record. Such
      # disagreement stays indeterminate and leaves stored state unchanged.
      #
      # A definitive negative from Approximated still demotes through the Array
      # branch above. TxtVerifier also keeps its normal three-outcome contract;
      # this strategy owns the extra corroboration rule because it alone has an
      # upstream result to compare with the native answer.
      #
      # An indeterminate upstream result gets one native TXT lookup. If that
      # cannot settle the result, the caller stays indeterminate. A second
      # diagnostic request would not change behavior and would bypass
      # VerifyDomain's per-domain bulk pacing, so no probe is issued.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @param match_records [Array<Hash>] 'records' from the API response
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def classify_ownership(custom_domain, match_records)
        if match_records.any? { |record| record['match'] == true }
          return { validated: true, message: 'TXT record validated', data: match_records }
        end

        looked_up = !match_records.empty? &&
                    match_records.all? { |record| record['actual_values'].is_a?(Array) }

        if looked_up
          seen    = match_records.flat_map { |record| record['actual_values'] }
          message = if seen.empty?
            'TXT record not found'
          else
            "TXT record mismatch (#{seen.size} value(s) found, exactly one matching value required)"
          end
          return { validated: false, message: message, data: match_records }
        end

        OT.lw "[ApproximatedStrategy] Indeterminate TXT check for #{custom_domain.display_domain}: " \
              "#{match_records.inspect}"

        classify_native(custom_domain, match_records)
      end

      # The upstream checker could not be asked (no API key, non-200, client
      # exception). Settled by the native lookup exactly like an indeterminate
      # upstream answer, so the outcome is validated / failed on DNS evidence
      # or indeterminate, and VerifyDomain's confirmation window bounds how
      # long an indeterminate run holds `verified`. A deployment whose API key
      # is missing or revoked therefore keeps confirming its domains natively.
      #
      # The NXDOMAIN probe is skipped: it needs the same upstream call.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @param reason [String] why upstream gave no answer
      # @param error [Object, nil] upstream response body, when there is one
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def upstream_unavailable(custom_domain, reason, error: nil)
        OT.lw "[ApproximatedStrategy] Upstream TXT check unavailable for #{custom_domain.display_domain}: #{reason}"

        result         = classify_native(custom_domain, [], unavailable: reason)
        result[:error] = error if error
        result
      rescue StandardError => ex
        # Ours, not the customer's DNS (e.g. the domain could not produce its
        # validation record).
        OT.le "[ApproximatedStrategy] Native fallback failed for #{custom_domain.display_domain}: " \
              "#{ex.class}: #{ex.message}"
        { validated: nil, indeterminate: true, message: "#{reason}; native lookup error: #{ex.message}" }
      end

      # Settles an indeterminate upstream result with our own TXT lookup.
      # See classify_ownership for the reasoning.
      #
      # :data keeps the upstream records first and appends the native record,
      # so the outcome log shows what both checkers saw.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @param match_records [Array<Hash>] upstream 'records' (indeterminate)
      # @param unavailable [String, nil] set when upstream was never asked or
      #   did not answer 200 (see #upstream_unavailable)
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def classify_native(custom_domain, match_records, unavailable: nil)
        native = txt_verifier.verify(custom_domain.validation_record, custom_domain.txt_validation_value)
        data   = match_records + Array(native[:data])

        # A false without :data is TxtVerifier declining to look (no challenge
        # configured). That is not an answer from DNS, so it does not demote.
        definitive = native[:validated] == true || (native[:validated] == false && native[:data])

        if definitive && native[:validated] == false && custom_domain.verified == true
          return {
            validated: nil,
            indeterminate: true,
            message: "#{native[:message]} (native lookup negative; upstream checker indeterminate; " \
                     'previously verified domain left unchanged)',
            data: data,
            source: native[:source],
          }
        end

        if definitive
          upstream = unavailable ? "upstream checker unavailable: #{unavailable}" : 'upstream checker indeterminate'
          return {
            validated: native[:validated],
            message: "#{native[:message]} (native lookup; #{upstream})",
            data: data,
            source: native[:source],
          }
        end

        message = if unavailable
          "Upstream DNS checker unavailable (indeterminate; #{unavailable})"
        else
          'Upstream DNS checker returned no result (indeterminate)'
        end

        {
          validated: nil,
          indeterminate: true,
          message: "#{message}; native lookup: #{native[:message]}",
          data: data,
        }
      end
    end
  end
end
