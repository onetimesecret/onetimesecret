# lib/onetime/operations/domains/probe.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) diagnostic operation — see decision D3 in
# lib/onetime/operations/README.md. The custom-domain model + its invariants are
# owned by the domains bounded context, whose incumbent operations home is
# lib/onetime/operations (verify_domain.rb, provision_sender_domain.rb, …). The
# domain toolbox verbs live here alongside them, under the Domains:: namespace.
#
# Loaded at the call site (colonel logic + CLI), so require net/http deps
# explicitly — the same convention the CLI command followed.
require 'net/http'
require 'openssl'

module Onetime
  module Operations
    module Domains
      # HTTPS probe of a custom domain — the SINGLE implementation of the probe
      # verb (epic #43 / D3). Makes one outbound HTTPS request to confirm the
      # domain serves traffic and inspects the presented TLS certificate.
      #
      # READ-ONLY: a probe reaches out over the network but mutates NOTHING in our
      # data store, so — like the orphaned scan / system read-outs — it records NO
      # {Onetime::AdminAuditEvent} (CONTRACT 4: audit is for mutations). The
      # `bin/ots domains probe` CLI and the colonel endpoint
      # (`GET /api/colonel/domains/:extid/probe`) are thin adapters over it.
      #
      # ## Behavioural parity (bit-for-bit)
      #
      # The probe logic is lifted verbatim from `DomainsProbeCommand#probe_domain`
      # (build client → start connection → capture peer cert → GET → classify
      # health). The returned Hash has the IDENTICAL shape and health taxonomy the
      # CLI produced, so `bin/ots domains probe --json` emits the same JSON. The op
      # takes a bare `hostname` (the CLI passed `domain.display_domain`); it does no
      # model lookup of its own.
      class Probe
        # @param hostname [String] the domain to probe (e.g. display_domain).
        # @param timeout [Integer] connect/read timeout in seconds (CLI default 10).
        # @param insecure [Boolean] skip TLS verification (debugging only; CLI flag).
        def initialize(hostname:, timeout: 10, insecure: false)
          @hostname = hostname.to_s
          @timeout  = timeout
          @insecure = insecure
        end

        # @return [Hash] the probe result (timestamp/domain/url + http/ssl/health).
        #   Same shape the CLI's `probe_domain` returned.
        def call
          result = {
            timestamp: Time.now.utc.iso8601,
            domain: @hostname,
            url: "https://#{@hostname}",
          }

          begin
            uri  = URI.parse("https://#{@hostname}")
            http = build_http_client(uri)
            cert = nil

            response = http.start do |client|
              # Capture cert while the connection is open.
              cert                  = client.peer_cert
              request               = Net::HTTP::Get.new(uri.request_uri)
              request['User-Agent'] = 'OTS-Domain-Probe/1.0'
              client.request(request)
            end

            result[:http] = {
              status_code: response.code.to_i,
              status_message: response.message,
              success: response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection),
            }

            result[:ssl]    = extract_ssl_info_from_cert(cert)
            result[:health] = determine_health(result)
          rescue OpenSSL::SSL::SSLError => ex
            result[:http]   = { error: 'SSL Error', message: ex.message }
            result[:ssl]    = { valid: false, error: ex.message }
            result[:health] = 'ssl_error'
          rescue Errno::ECONNREFUSED => ex
            result[:http]   = { error: 'Connection Refused', message: ex.message }
            result[:health] = 'connection_refused'
          rescue Errno::ECONNRESET => ex
            result[:http]   = { error: 'Connection Reset', message: ex.message }
            result[:health] = 'connection_reset'
          rescue Net::OpenTimeout, Net::ReadTimeout => ex
            result[:http]   = { error: 'Timeout', message: ex.message }
            result[:health] = 'timeout'
          rescue SocketError => ex
            result[:http]   = { error: 'DNS Resolution Failed', message: ex.message }
            result[:health] = 'dns_error'
          rescue StandardError => ex
            result[:http]   = { error: ex.class.name, message: ex.message }
            result[:health] = 'error'
          end

          result
        end

        private

        def build_http_client(uri)
          http              = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.open_timeout = @timeout
          http.read_timeout = @timeout

          http.verify_mode = if @insecure
            OpenSSL::SSL::VERIFY_NONE
          else
            OpenSSL::SSL::VERIFY_PEER
          end

          http
        end

        def extract_ssl_info_from_cert(cert)
          return { valid: false, error: 'No certificate' } unless cert

          now               = Time.now
          not_before        = cert.not_before
          not_after         = cert.not_after
          days_until_expiry = ((not_after - now) / 86_400).to_i

          {
            valid: true,
            subject: cert.subject.to_s,
            issuer: cert.issuer.to_s,
            not_before: not_before.iso8601,
            not_after: not_after.iso8601,
            days_until_expiry: days_until_expiry,
            expired: now > not_after,
            not_yet_valid: now < not_before,
          }
        rescue StandardError => ex
          { valid: false, error: ex.message }
        end

        def determine_health(result)
          http = result[:http]
          ssl  = result[:ssl]

          return 'error' if http[:error]
          return 'ssl_invalid' unless ssl[:valid]
          return 'ssl_expired' if ssl[:expired]
          return 'ssl_expiring_soon' if ssl[:days_until_expiry] && ssl[:days_until_expiry] < 7

          if http[:success]
            'healthy'
          else
            'http_error'
          end
        end
      end
    end
  end
end
