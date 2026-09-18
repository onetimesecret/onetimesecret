# lib/onetime/domain_validation/approximated_strategy.rb
#
# frozen_string_literal: true

require 'securerandom'

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
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def validate_ownership(custom_domain)
        api_key = Features.api_key

        if api_key.to_s.empty?
          return { validated: false, message: 'Approximated API key not configured' }
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
          {
            validated: false,
            message: "Validation check failed: #{res.code}",
            error: res.parsed_response,
          }
        end
      rescue StandardError => ex
        OT.le "[ApproximatedStrategy] Error validating #{custom_domain.display_domain}: #{ex.message}"
        { validated: false, message: "Error: #{ex.message}" }
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
      # Callers must treat nil as "no answer" and leave the stored verified
      # flag untouched (VerifyDomain#persist_changes does). Collapsing a failed
      # upstream lookup into `false` demoted correctly-configured domains on
      # every refresh run.
      #
      # When upstream is indeterminate, our own lookup (TxtVerifier) decides,
      # and its three outcomes pass through with their meaning intact:
      #
      #   native true   -> validated: true
      #   native false  -> validated: false. The resolver stated NXDOMAIN, or
      #                    NOERROR without TXT data, or values that are not
      #                    "exactly one, matching". This demotes a verified
      #                    domain (an operator override still holds it, in
      #                    VerifyDomain).
      #   native nil    -> validated: nil. SERVFAIL, REFUSED, a timeout or an
      #                    exception is no answer, from either checker.
      #
      # Why a native false demotes even though upstream gave no answer:
      #
      #   - `verified` asserts that the customer controls the domain now. When
      #     the proof is gone (record removed, zone lapsed, domain changed
      #     hands) the assertion has to go with it.
      #   - A healthy upstream would have reported the same empty or different
      #     values and demoted through the Array branch above. The native path
      #     reaches the same result, it does not add a new way to lose
      #     `verified`.
      #   - TxtVerifier's false has to mean one thing under both strategies.
      #   - It cannot bring back the false demotions: those came from reading
      #     a failed lookup as a mismatch, and TxtVerifier keeps every failed
      #     lookup in nil. A false needs a definitive response code.
      #
      # The NXDOMAIN sentinel probe therefore only runs when the native lookup
      # is indeterminate too. It reveals which upstream state covers "record
      # does not exist":
      #
      #   sentinel actual_values is []     -> Approximated distinguishes NXDOMAIN
      #                                       from lookup failure; a `false` on
      #                                       the real check is an upstream
      #                                       fault, not a deletion.
      #   sentinel actual_values is false  -> Approximated conflates NXDOMAIN
      #                                       and SERVFAIL, so a deleted TXT
      #                                       record is only ever demoted by
      #                                       the native lookup.
      #
      # The probe never changes the outcome; it is recorded so operators can
      # tell "upstream checker is broken today" apart from "upstream checker
      # never reports a deleted TXT record."
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

      # Settles an indeterminate upstream result with our own TXT lookup.
      # See classify_ownership for the reasoning.
      #
      # :data keeps the upstream records first and appends the native record,
      # so the log line for a demotion shows what both checkers saw.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @param match_records [Array<Hash>] upstream 'records' (indeterminate)
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def classify_native(custom_domain, match_records)
        native = txt_verifier.verify(custom_domain.validation_record, custom_domain.txt_validation_value)
        data   = match_records + Array(native[:data])

        # A false without :data is TxtVerifier declining to look (no challenge
        # configured). That is not an answer from DNS, so it does not demote.
        definitive = native[:validated] == true || (native[:validated] == false && native[:data])

        if definitive
          return {
            validated: native[:validated],
            message: "#{native[:message]} (native lookup; upstream checker indeterminate)",
            data: data,
            source: native[:source],
          }
        end

        nxdomain_probe = probe_nxdomain_semantics(custom_domain)
        message        = case nxdomain_probe
                         when :distinguishes
                           'Upstream DNS checker returned no result (indeterminate; ' \
                           'NXDOMAIN probe shows the checker distinguishes missing records — ' \
                           'this false is a transient upstream fault)'
                         when :conflates
                           'Upstream DNS checker returned no result (indeterminate; ' \
                           'NXDOMAIN probe shows the checker conflates NXDOMAIN with lookup ' \
                           'failure — only the native lookup can report a deleted TXT record)'
                         else
                           'Upstream DNS checker returned no result (indeterminate)'
                         end

        {
          validated: nil,
          indeterminate: true,
          nxdomain_probe: nxdomain_probe,
          message: "#{message}; native lookup: #{native[:message]}",
          data: data,
        }
      end

      # Probes Approximated's NXDOMAIN semantics with a single call against a
      # random subdomain of the customer's zone that cannot resolve.
      #
      # Approximated's contract for 'actual_values' is either an Array of
      # values it saw or the literal `false` "when DNS resolution or the
      # record-type lookup failed." The probe reveals which of those two
      # states covers NXDOMAIN for this deployment.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Symbol] :distinguishes, :conflates, :unknown
      #
      def probe_nxdomain_semantics(custom_domain)
        api_key = Features.api_key
        return :unknown if api_key.to_s.empty?

        sentinel = "_nxdomain-probe-#{SecureRandom.uuid}.#{custom_domain.display_domain}"
        records  = [{ type: 'TXT', address: sentinel, match_against: 'probe-should-not-match' }]

        res = client.check_records_match_exactly(api_key, records)
        return :unknown unless res.code == 200

        record = Array(res.parsed_response['records']).first
        return :unknown if record.nil?

        case record['actual_values']
        when Array
          # A non-empty array means a wildcard or misconfigured zone answered
          # the probe. That is not evidence about NXDOMAIN handling.
          record['actual_values'].empty? ? :distinguishes : :unknown
        when false
          :conflates
        else
          :unknown
        end
      rescue StandardError => ex
        OT.lw "[ApproximatedStrategy] NXDOMAIN probe failed for #{custom_domain.display_domain}: #{ex.message}"
        :unknown
      end
    end
  end
end
