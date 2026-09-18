# lib/onetime/domain_validation/tls_probe.rb
#
# frozen_string_literal: true

require 'openssl'
require 'socket'

require 'onetime/http/guard'
require_relative 'address_resolver'

module Onetime
  module DomainValidation
    # TlsProbe - Does this hostname resolve, and does it serve a certificate
    # that is valid for it?
    #
    # Used by CaddyOnDemandStrategy#check_status, where no provider API can
    # answer that for us. The probe resolves the name, opens TCP:443 with
    # SNI set to the hostname, completes a TLS handshake with full
    # verification (chain + hostname) and closes. No application data is sent.
    #
    # Each answer is one of three outcomes, the same discipline as the TXT
    # check. nil means "could not tell" and must never change stored state:
    #
    #   is_resolving  true   the name has at least one A/AAAA record
    #                 false  NXDOMAIN, or NOERROR with no address records
    #                 nil    SERVFAIL / REFUSED / timeout / any error
    #
    #   has_ssl       true   verified handshake completed
    #                 false  the host answered and did not present a
    #                        certificate valid for the name (TLS alert,
    #                        verification or hostname failure, connection
    #                        refused or dropped), or the name does not resolve
    #                 nil    we could not reach it (timeout, no route, probe
    #                        refused by the egress guard) or any other error
    #
    # The hostname is customer-controlled, so this is an outbound connection
    # to a user-supplied host. It goes through the shared egress guard
    # (Onetime::Http::Guard): the name is resolved once, the whole address set
    # is rejected if any address is loopback/private/link-local/reserved, and
    # the connection is dialled to a vetted IP — never re-resolved — with the
    # hostname used only for SNI and certificate verification.
    #
    # An internationalised name is probed in its A-label form (AsciiHostname):
    # that is what DNS carries, what a client sends as SNI and what the
    # certificate names. A name with no A-label form is "could not tell".
    #
    # Time budget per probe: DNS 3s (AddressResolver) + connect and handshake
    # 5s together, so at most 8s, and that only when both stages time out.
    #
    class TlsProbe
      HTTPS_PORT      = 443
      CONNECT_TIMEOUT = 2 # seconds, one TCP connect
      TLS_TIMEOUT     = 5 # seconds, all connects plus the handshake

      Guard = Onetime::Http::Guard

      # Raised when the TLS budget runs out mid-handshake.
      class HandshakeTimeout < StandardError; end

      # "We could not reach it": says nothing about the customer's setup.
      UNREACHABLE_ERRORS = [
        HandshakeTimeout,
        Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::EADDRNOTAVAIL,
        IO::TimeoutError,
      ].freeze

      # "It answered, without a certificate valid for this name."
      NO_CERTIFICATE_ERRORS = [
        OpenSSL::SSL::SSLError,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EPIPE,
        EOFError,
      ].freeze

      # @!attribute is_resolving [Boolean, nil]
      # @!attribute has_ssl      [Boolean, nil]
      # @!attribute addresses    [Array<String>] what the name resolved to
      # @!attribute connected_to [String, nil] the vetted IP that was dialled
      # @!attribute certificate  [OpenSSL::X509::Certificate, nil] on has_ssl: true
      # @!attribute message      [String]
      Result = Data.define(:is_resolving, :has_ssl, :addresses, :connected_to, :certificate, :message) do
        def initialize(addresses: [], connected_to: nil, certificate: nil, **)
          super
        end

        # Neither answer is known; the caller should leave stored state alone.
        def indeterminate?
          is_resolving.nil? && has_ssl.nil?
        end
      end

      # @param resolver_factory [#call] returns an object with #lookup(hostname)
      #   (AddressResolver::Answer) and #close
      # @param connector [#call] (ip, port, timeout) -> connected TCP socket
      # @param cert_store [OpenSSL::X509::Store, nil] trust anchors; nil uses
      #   the system defaults
      #
      # All three are seams so specs never leave the process.
      def initialize(resolver_factory: -> { AddressResolver.new }, connector: nil, cert_store: nil)
        @resolver_factory = resolver_factory
        @connector        = connector || method(:tcp_connect)
        @cert_store       = cert_store
      end

      # @param hostname [String] the custom domain as the customer's visitors type it
      # @return [Result]
      def probe(hostname)
        host = ascii_hostname(hostname)
        return unknown("Hostname #{hostname.inspect} cannot be probed") if host.nil?

        answer = resolve(host)
        return unknown("DNS lookup failed (#{answer.rcode_name})") unless answer.definitive?
        unless answer.resolves?
          return Result.new(is_resolving: false, has_ssl: false, message: "No A/AAAA records (#{answer.rcode_name})")
        end

        check_certificate(host, answer.addresses)
      rescue StandardError => ex
        OT.lw "[TlsProbe] Probe of #{host} failed: #{ex.class}: #{ex.message}"
        unknown("Probe failed: #{ex.class}")
      end

      private

      def unknown(message)
        Result.new(is_resolving: nil, has_ssl: nil, message: message)
      end

      # A name the wire format cannot carry would come back NXDOMAIN for the
      # wrong reason, so it is not looked up at all.
      #
      # @return [String, nil]
      def ascii_hostname(hostname)
        AsciiHostname.call(hostname)
      rescue AsciiHostname::ConversionError => ex
        OT.lw "[TlsProbe] Not probing #{hostname.inspect}: #{ex.message}"
        nil
      end

      def resolve(host)
        resolver = @resolver_factory.call
        resolver.lookup(host)
      ensure
        begin
          resolver&.close
        rescue StandardError => ex
          OT.lw "[TlsProbe] Error closing resolver: #{ex.class}: #{ex.message}"
        end
      end

      # The name resolves; everything below only decides has_ssl.
      def check_certificate(host, addresses)
        vetted   = Guard.validate_addresses!(host, addresses)
        deadline = monotonic + TLS_TIMEOUT
        dialled  = nil

        certificate = dial_each(vetted) do |ip|
          dialled = ip
          handshake(@connector.call(ip, HTTPS_PORT, connect_budget(deadline)), host, deadline)
        end

        resolving(addresses, true, "Valid certificate presented for #{host}", connected_to: dialled, certificate: certificate)
      rescue Guard::Blocked => ex
        # Not dialled. The name does resolve, which is all is_resolving claims.
        OT.lw "[TlsProbe] Not probing #{host}: #{ex.message}"
        resolving(addresses, nil, 'Resolves to a non-public address; certificate not checked')
      rescue *NO_CERTIFICATE_ERRORS => ex
        OT.ld "[TlsProbe] No valid certificate for #{host} at #{dialled}: #{ex.class}: #{ex.message}"
        resolving(addresses, false, "No valid certificate for #{host}: #{ex.message}", connected_to: dialled)
      rescue *UNREACHABLE_ERRORS => ex
        OT.lw "[TlsProbe] Could not reach #{host} at #{dialled}: #{ex.class}: #{ex.message}"
        resolving(addresses, nil, "Could not reach #{host} on port #{HTTPS_PORT}", connected_to: dialled)
      end

      def resolving(addresses, has_ssl, message, **)
        Result.new(is_resolving: true, has_ssl: has_ssl, addresses: addresses, message: message, **)
      end

      # Same walk as Guard.try_each_address!, over addresses this class
      # resolved itself: the next vetted address is tried only on the
      # connect errors that return immediately. A timeout ends the probe, so
      # a multi-address name cannot multiply the time budget.
      #
      # When nothing connects, a refusal outranks "no route": the refusal came
      # from the customer's host, while an unroutable family (commonly IPv6)
      # is a property of our own network.
      def dial_each(vetted)
        refused    = nil
        last_error = nil
        vetted.each do |ip|
          return yield(ip)
        rescue *Guard::CONNECT_FALLBACK_ERRNOS => ex
          refused  ||= ex if ex.is_a?(Errno::ECONNREFUSED)
          last_error = ex
        end
        raise(refused || last_error) # never nil: validate_addresses! raises on empty
      end

      def connect_budget(deadline)
        remaining = deadline - monotonic
        raise HandshakeTimeout, 'no time left to connect' unless remaining.positive?

        [remaining, CONNECT_TIMEOUT].min
      end

      # Dials the vetted IP literal, so nothing is resolved here.
      def tcp_connect(ip, port, timeout)
        Socket.tcp(ip, port, connect_timeout: timeout)
      end

      # Completes a verified handshake and closes. Chain and hostname are both
      # checked during the handshake (verify_hostname with SNI set);
      # post_connection_check repeats the hostname check on the peer
      # certificate so the result does not rest on one OpenSSL setting.
      #
      # @return [OpenSSL::X509::Certificate]
      # @raise [OpenSSL::SSL::SSLError, HandshakeTimeout]
      def handshake(tcp, host, deadline)
        ssl            = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
        ssl.sync_close = true
        ssl.hostname   = host # SNI, and the name verify_hostname checks

        loop do
          case ssl.connect_nonblock(exception: false)
          when :wait_readable then wait(deadline) { |left| tcp.wait_readable(left) }
          when :wait_writable then wait(deadline) { |left| tcp.wait_writable(left) }
          else break
          end
        end

        ssl.post_connection_check(host)
        ssl.peer_cert
      ensure
        ssl ? ssl.close : tcp&.close
      end

      def wait(deadline)
        remaining = deadline - monotonic
        return if remaining.positive? && yield(remaining)

        raise HandshakeTimeout, 'timed out during TLS handshake'
      end

      def ssl_context
        params              = { verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true }
        params[:cert_store] = @cert_store if @cert_store

        OpenSSL::SSL::SSLContext.new.tap do |ctx|
          ctx.set_params(params) # default trust store unless one was injected
          ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
