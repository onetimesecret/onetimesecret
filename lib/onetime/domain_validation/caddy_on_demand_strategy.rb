# lib/onetime/domain_validation/caddy_on_demand_strategy.rb
#
# frozen_string_literal: true

require 'time'

require_relative 'txt_verifier'
require_relative 'tls_probe'

module Onetime
  module DomainValidation
    # CaddyOnDemandStrategy - Caddy's on_demand_tls certificate management.
    #
    # Use this when using Caddy's on-demand TLS feature. Caddy calls the
    # internal ACME endpoint (apps/internal/acme) to ask whether a domain is
    # allowed before issuing a certificate, and that endpoint answers from
    # CustomDomain#ready?, which requires `verified`.
    #
    # Two separate proofs are involved and only one of them is Caddy's:
    #
    #   - Ownership: this strategy checks the TXT challenge record with our
    #     own DNS lookup (TxtVerifier), the same "exactly one matching value"
    #     rule the Approximated strategy applies.
    #   - Certificate issuance: Caddy completes the ACME challenge. That shows
    #     the name currently resolves to this deployment. It says nothing
    #     about which account, if any, controls the domain, so it is never
    #     read as ownership (ADR-016).
    #
    # Caddy exposes no per-domain status, so #check_status probes the domain
    # itself (TlsProbe): does the name resolve, and does port 443 present a
    # certificate valid for it. That is display and readiness state only.
    #
    class CaddyOnDemandStrategy < BaseStrategy
      MODE = 'caddy_on_demand'

      # Marks a stored `vhost` blob as written by this strategy's probe rather
      # than copied from an Approximated API response.
      VHOST_SOURCE = 'tls_probe'

      attr_reader :config, :txt_verifier, :tls_probe

      # @param config [Hash] Application configuration (typically OT.conf)
      # @param txt_verifier [#verify] Ownership checker (default: TxtVerifier).
      # @param tls_probe [#probe] Status checker (default: TlsProbe).
      #   Both are injected so specs never touch the network.
      #
      def initialize(config, txt_verifier: TxtVerifier.new, tls_probe: TlsProbe.new)
        @config       = config
        @txt_verifier = txt_verifier
        @tls_probe    = tls_probe
      end

      # Validates domain ownership via the TXT challenge record.
      #
      # Three outcomes, passed through from TxtVerifier:
      #
      #   validated: true   exactly one TXT value, equal to the challenge
      #   validated: false  the resolver stated the record is missing or
      #                     different (demotes a verified domain, unless an
      #                     operator override holds it)
      #   validated: nil    the lookup produced no answer; stored state is
      #                     left alone (VerifyDomain#persist_changes)
      #
      # with one exception to nil, see #never_confirmed?.
      #
      # A domain with no challenge value also fails. TxtVerifier omits :data
      # for that case, but the :mode added here means VerifyDomain stores the
      # false: a domain with nothing to prove ownership is not verified.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def validate_ownership(custom_domain)
        result = txt_check(custom_domain)
        never_confirmed?(custom_domain, result) ? unconfirmed(result) : result
      end

      # Certificate issuance handled automatically by Caddy.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Delegated certificate response
      #
      def request_certificate(_custom_domain)
        {
          status: 'delegated',
          message: 'Certificate issuance delegated to Caddy',
          mode: MODE,
        }
      end

      # Reports whether the domain resolves and serves a valid certificate,
      # from our own probe (TlsProbe): Caddy has no status API to ask.
      #
      # How each answer reaches storage (VerifyDomain#persist_changes):
      #
      #   is_resolving  true/false is stored in `resolving`; nil is skipped.
      #   has_ssl       lives only inside the `vhost` blob (:data). The blob
      #                 is rewritten on every check that knows is_resolving,
      #                 so its status and is_resolving never disagree with
      #                 `resolving`. When has_ssl is unknown (the probe could
      #                 not reach port 443, or the egress guard refused the
      #                 address) the stored has_ssl and certificate dates are
      #                 carried into the new blob, so an unknown never
      #                 overwrites a known value. A blob left by the
      #                 Approximated strategy is not overwritten at all:
      #                 after a cutover it is the only record that a remote
      #                 vhost exists, and the RemoveOrphanedApproximatedVhosts
      #                 chore clears it once that vhost is dealt with.
      #   both nil      no :mode and no :data, the same shape Approximated
      #                 returns when its API call fails: nothing stored
      #                 changes and vhost_fetch_failed_at is set, which the UI
      #                 shows as "last check failed".
      #
      # `resolving` means only that the name has an address record. It cannot
      # wait for the certificate: the ACME ask endpoint requires `resolving`
      # before Caddy is allowed to obtain one.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#check_status
      #
      def check_status(custom_domain)
        result = tls_probe.probe(custom_domain.display_domain)
        return { ready: false, has_ssl: nil, is_resolving: nil, message: result.message } if result.indeterminate?

        status        = {
          ready: result.is_resolving == true && result.has_ssl == true,
          has_ssl: result.has_ssl,
          is_resolving: result.is_resolving,
          message: result.message,
          mode: MODE,
        }
        # TlsProbe never knows has_ssl without knowing is_resolving.
        status[:data] = vhost_data(custom_domain, result) if !result.is_resolving.nil? && owns_vhost?(custom_domain)
        status
      rescue StandardError => ex
        # TlsProbe rescues its own work; this is a failure of ours and says
        # nothing about the domain.
        OT.le "[CaddyOnDemandStrategy] Error checking status for #{custom_domain.display_domain}: " \
              "#{ex.class}: #{ex.message}"
        { ready: false, has_ssl: nil, is_resolving: nil, message: "Error: #{ex.message}" }
      end

      # No-op for Caddy - certificate lifecycle managed by Caddy.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] No-op response
      #
      def delete_vhost(_custom_domain)
        {
          deleted: false,
          message: 'No-op: certificate lifecycle managed by Caddy',
          mode: MODE,
        }
      end

      # DNS widget not available for Caddy strategy.
      #
      # @return [Hash] Unavailable response
      #
      def get_dns_widget_token
        {
          available: false,
          message: 'DNS widget not available with Caddy on-demand TLS',
          mode: MODE,
        }
      end

      # @return [Boolean] false - Caddy does not support DNS widget
      def supports_dns_widget?
        false
      end

      # @return [Boolean] false - Caddy manages certificates, not this strategy
      def manages_certificates?
        false
      end

      # @return [Boolean] true - a pass means TxtVerifier found the record
      def proves_ownership?
        true
      end

      private

      def txt_check(custom_domain)
        txt_verifier
          .verify(custom_domain.validation_record, custom_domain.txt_validation_value)
          .merge(mode: MODE)
      rescue StandardError => ex
        # TxtVerifier rescues its own lookup. Anything reaching here is ours
        # (e.g. the domain could not produce its validation record), which is
        # not evidence about the customer's DNS.
        OT.le "[CaddyOnDemandStrategy] Error validating #{custom_domain.display_domain}: " \
              "#{ex.class}: #{ex.message}"
        { validated: nil, indeterminate: true, message: "Error: #{ex.message}", mode: MODE }
      end

      # An indeterminate lookup leaves `verified` alone so that a resolver
      # failure cannot undo a verification a TXT check once established.
      # verified_confirmed_at records that check. When it is nil and the
      # domain is nevertheless verified, the flag was set before this strategy
      # checked anything, so there is no earlier proof for the hold to protect
      # — and with the status probe now filling in `resolving`, holding it
      # would make the domain ready? and let the ACME ask endpoint answer for
      # it. Such a domain gets a definitive false instead.
      #
      # Not affected: an unverified domain (nil and false store the same, and
      # nil keeps the "could not tell" report), a domain with a recorded
      # confirmation, and a domain held by an operator override
      # (VerifyDomain#override_held? applies to this false like any other).
      #
      # A domain verified under another strategy before verified_confirmed_at
      # existed also lands here if its first check is indeterminate. It is
      # promoted again by the next check that finds the record.
      def never_confirmed?(custom_domain, result)
        result[:indeterminate] == true &&
          custom_domain.verified == true && # boolean_field native
          custom_domain.verified_confirmed_at.nil?
      end

      def unconfirmed(result)
        result.except(:indeterminate).merge(
          validated: false,
          message: "Ownership has not been confirmed by a TXT check (#{result[:message]})",
        )
      end

      # True when the stored blob is empty or was written by this strategy.
      def owns_vhost?(custom_domain)
        stored = custom_domain.parse_vhost
        !stored.is_a?(Hash) || stored.empty? || stored['source'] == VHOST_SOURCE
      end

      # The subset of Approximated's vhost payload the domain pages read,
      # filled from the probe. `status` reuses Approximated's values where the
      # UI keys off them (ACTIVE_SSL -> active, DNS_INCORRECT -> warning).
      #
      # Only called for a blob this strategy owns and a known is_resolving.
      def vhost_data(custom_domain, result)
        ssl    = ssl_fields(custom_domain, result)
        status = if ssl['has_ssl'] == true then 'ACTIVE_SSL'
                 elsif result.is_resolving then 'PENDING_SSL'
                 else
                   'DNS_INCORRECT'
                 end

        {
          'incoming_address' => custom_domain.display_domain,
          'status' => status,
          'status_message' => result.message,
          'is_resolving' => result.is_resolving,
          'dns_pointed_at' => result.connected_to || result.addresses.first,
          'last_monitored_unix' => OT.now.to_i,
          'source' => VHOST_SOURCE,
        }.merge(ssl).compact
      end

      # has_ssl and the certificate dates: from the probe when it knows, else
      # whatever the previous check stored.
      def ssl_fields(custom_domain, result)
        if result.has_ssl.nil?
          stored = custom_domain.parse_vhost
          return stored.is_a?(Hash) ? stored.slice('has_ssl', 'ssl_active_from', 'ssl_active_until') : {}
        end

        {
          'has_ssl' => result.has_ssl,
          'ssl_active_from' => iso8601(result.certificate&.not_before),
          'ssl_active_until' => iso8601(result.certificate&.not_after),
        }
      end

      def iso8601(time)
        time&.utc&.iso8601
      end
    end
  end
end
