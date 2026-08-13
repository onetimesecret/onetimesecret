# lib/onetime/http/safe_fetch.rb
#
# frozen_string_literal: true

require 'ipaddr'
require 'net/http'
require 'openssl'
require 'uri'
require 'stringio'
require 'fastimage'

require_relative 'guard'

module Onetime
  module Http
    # SSRF-guarded HTTP fetcher for pulling third-party assets (e.g. a custom
    # domain's favicon, #3780) from arbitrary, attacker-influenced URLs.
    #
    # The guard is deny-by-default and fail-closed. Every fetch:
    #   1. accepts only https:// on port 443 (no scheme/port downgrade surface),
    #   2. resolves the host's A + AAAA records and rejects the request if ANY
    #      resolved address is private/link-local/loopback/metadata — the range
    #      check itself is delegated to the shared Onetime::Http::Guard
    #      blocklists (Guard::Blocked is translated to BlockedTarget at this
    #      class's boundary, so callers keep rescuing SafeFetch errors only),
    #   3. pins each TCP connect to one exact validated IP (http.ipaddr=) so no
    #      second DNS resolution happens at connect time — closing the classic
    #      validate-then-reresolve (DNS-rebinding) window. Addresses are dialed
    #      IPv4-first, falling through the remaining validated addresses on
    #      connect-level route errors (broken dual-stack hosts resolve AAAA
    #      records they cannot route to),
    #   4. never lets Net::HTTP auto-follow redirects; each hop is re-checked
    #      and re-validated against the guard, with a redirect cap,
    #   5. enforces a byte ceiling both on the declared Content-Length AND while
    #      streaming the body (never buffers unbounded), and
    #   6. validates the payload by magic bytes (FastImage), accepting only PNG
    #      and ICO and explicitly rejecting SVG/XML.
    #
    # NOTE: lives under Onetime::Http (NOT Onetime::Net) on purpose — a module
    # named Net here would shadow the stdlib `Net` for every bare `Net::` under
    # the Onetime namespace and break unrelated callers (e.g. Operations::
    # Domains::Probe). The stdlib is still referenced as ::Net below for clarity.
    class SafeFetch
      Result = Struct.new(:body, :content_type, :final_url, keyword_init: true)

      class Error < Onetime::Problem; end
      # resolved to private/link-local/metadata, or bad scheme/port/host
      class BlockedTarget < Error; end
      class TooManyRedirects < Error; end
      class ResponseTooLarge < Error; end
      class DisallowedContentType < Error; end
      # transient → retriable by the caller
      class FetchTimeout < Error; end

      ALLOWED_SCHEMES = %w[https].freeze
      ALLOWED_PORTS   = [443].freeze

      REDIRECT_CODES  = [301, 302, 303, 307, 308].freeze
      SUCCESS_CODES   = (200..299)

      # Connect-time failures that justify dialing the next validated address.
      # The list lives on the shared Guard (which also documents the
      # exclusions: timeouts — mapped here to retriable FetchTimeout — and all
      # post-connect errors) so every pinned-dial callsite falls back on the
      # same errno set.
      CONNECT_FALLBACK_ERRNOS = Guard::CONNECT_FALLBACK_ERRNOS

      DEFAULT_HEADERS = { 'user-agent' => 'OnetimeSecret-SafeFetch/1.0' }.freeze

      # The deny-by-default IP range lists live in the shared SSRF guard
      # (Onetime::Http::Guard::BLOCKED_V4/BLOCKED_V6) — the single source of
      # truth for every egress callsite. Note Guard's V6 list also blocks
      # Teredo (2001::/32), which SafeFetch's former local list lacked.

      # Magic-byte sniff family → the MIME we permit and canonicalize to. The
      # HTTP-declared Content-Type is never trusted for the accept decision.
      MIME_TO_SNIFF        = {
        'image/png' => :png,
        'image/x-icon' => :ico,
        'image/vnd.microsoft.icon' => :ico,
      }.freeze
      SNIFF_CANONICAL_MIME = { png: 'image/png', ico: 'image/x-icon' }.freeze

      # @param timeout [Numeric] per-hop connect+read timeout in seconds
      # @param max_bytes [Integer] hard ceiling on the response body
      # @param max_redirects [Integer] redirects followed before TooManyRedirects
      # @param allowed_content_types [Array<String>] permitted MIME allow-list;
      #   each entry is mapped to a magic-byte family, so an unknown MIME simply
      #   contributes nothing (deny-by-default).
      def initialize(timeout:, max_bytes:, max_redirects:, allowed_content_types:)
        @timeout               = timeout
        @max_bytes             = max_bytes
        @max_redirects         = max_redirects
        @allowed_content_types = Array(allowed_content_types)
        @allowed_types         = @allowed_content_types.filter_map { |mime| MIME_TO_SNIFF[mime] }.uniq
      end

      # Fetch and validate an image. Follows up to max_redirects redirects,
      # re-resolving and re-validating the host at EVERY hop.
      #
      # @return [Result] body (binary), content_type (sniffed MIME), final_url
      # @raise [BlockedTarget, TooManyRedirects, ResponseTooLarge,
      #   DisallowedContentType, FetchTimeout, Error]
      def get_image(url)
        fetch(url, redirects_left: @max_redirects, allow_html: false, deadline: new_deadline)
      end

      # Fetch text (favicon discovery HTML). Same SSRF guard and byte cap; no
      # image content validation. Returns the raw body string.
      #
      # @return [String]
      # @raise (see #get_image)
      def get_html(url)
        fetch(url, redirects_left: @max_redirects, allow_html: true, deadline: new_deadline).body
      end

      private

      # Orchestrates one hop: scheme/port check → resolve+validate → pinned GET
      # against the validated address list. On a redirect, re-enters itself with
      # the (re-validated) target and a decremented counter.
      def fetch(url, redirects_left:, allow_html:, deadline:)
        uri        = build_uri(url)
        enforce_scheme_and_port!(uri)
        check_deadline!(deadline, uri)
        candidates = resolve_and_validate!(uri.host)

        outcome = try_each_address(uri, candidates, allow_html, deadline)

        if outcome[0] == :redirect
          raise TooManyRedirects, "exceeded #{@max_redirects} redirects at #{uri}" if redirects_left <= 0

          target = absolutize(uri, outcome[1])
          return fetch(target, redirects_left: redirects_left - 1, allow_html: allow_html, deadline: deadline)
        end

        outcome[1] # the Result
      end

      # One hop, all validated addresses: dial each in order and return the
      # first interpreted response. Every candidate already passed the SSRF
      # guard and each dial stays pinned to one exact IP, so walking the list
      # is a reachability fallback (poor-man's Happy Eyeballs), not a widening
      # of the target set. When every address fails, the last errno propagates
      # unchanged — terminal for the caller, same as pre-fallback behavior.
      # The Net timeout → FetchTimeout mapping wraps the transport seam here
      # (not inside it) so both connect- and read-time timeouts are normalized
      # on the real path.
      def try_each_address(uri, candidate_ips, allow_html, deadline)
        last_error = nil
        candidate_ips.each do |ip|
          return with_pinned_response(uri, ip) do |resp|
            interpret_response(resp, uri, allow_html, deadline)
          end
        rescue ::Net::OpenTimeout, ::Net::ReadTimeout => ex
          raise FetchTimeout, "timeout fetching #{uri}: #{ex.message}"
        rescue *CONNECT_FALLBACK_ERRNOS => ex
          last_error = ex
        end
        raise last_error # never nil: resolve_and_validate! raises on empty
      end

      # Per-call monotonic wall-clock budget spanning ALL redirect hops and the
      # streamed body read — bounds how long one get_image/get_html can pin a
      # worker thread (slowloris trickle × redirect fan-out). Worst-case overshoot
      # is deadline + one hop @timeout: we deliberately leave the socket timeouts
      # at @timeout (rather than shrinking to remaining-budget) to keep the
      # with_pinned_response test seam signature stable.
      def new_deadline
        monotonic_now + (@timeout * (@max_redirects + 1))
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def check_deadline!(deadline, context)
        raise FetchTimeout, "exceeded total fetch budget (#{context})" if monotonic_now > deadline
      end

      def build_uri(url)
        url.is_a?(URI::Generic) ? url : URI.parse(url.to_s)
      rescue URI::InvalidURIError => ex
        raise Error, "invalid URL #{url.inspect}: #{ex.message}"
      end

      def enforce_scheme_and_port!(uri)
        raise BlockedTarget, "scheme #{uri.scheme.inspect} not allowed" unless ALLOWED_SCHEMES.include?(uri.scheme)
        raise BlockedTarget, "missing host in #{uri}" if uri.host.to_s.empty?
        raise BlockedTarget, "port #{uri.port} not allowed" unless ALLOWED_PORTS.include?(uri.port)
      end

      # Resolve host A + AAAA, validate EVERY address, and fail closed: raise if
      # ANY resolved address is blocked (defeats one-public-one-private RRsets).
      # Returns ALL validated addresses ordered IPv4-first: resolvers commonly
      # list AAAA ahead of A, and a machine with an IPv6 address but no IPv6
      # route (broken dual-stack) would otherwise dial an unreachable v6 and
      # never try a perfectly good v4.
      #
      # Validation is delegated to Guard; resolution goes through this
      # instance's #resolve_addresses seam (not Guard's own resolver) so the
      # unit tryout can stub DNS per-instance. Guard::Blocked is translated to
      # BlockedTarget here so SafeFetch's error contract stays self-contained.
      # Unlike Guard.resolve_and_validate!, an IP-literal host is NOT accepted:
      # it resolves to nothing and is rejected as before (a literal would fail
      # TLS hostname verification anyway).
      def resolve_and_validate!(host)
        addrs = resolve_addresses(host)
        raise Guard::Blocked, "no A/AAAA records for #{host}" if addrs.empty?

        addrs.each do |addr|
          raise Guard::Blocked, "blocked address #{addr} for #{host}" if Guard.blocked_ip?(addr)
        end

        # Safe to parse: anything unparseable already failed closed in blocked_ip?.
        v4, v6 = addrs.uniq.partition { |addr| IPAddr.new(addr).ipv4? }
        v4 + v6
      rescue Guard::Blocked => ex
        raise BlockedTarget, ex.message
      end

      # DNS seam, isolated for testability (overridden in the unit tryout to
      # avoid real DNS). Forwards to Guard's resolver on the real path.
      # Returns an array of IP strings (both families).
      def resolve_addresses(host)
        Guard.resolve_addresses(host)
      end

      # Deny-by-default IP check, delegated to the shared Guard blocklists.
      # Fails closed on anything IPAddr cannot parse (encoded-loopback
      # smuggling like "2130706433" / "0x7f000001" is treated as blocked).
      def blocked_ip?(addr)
        Guard.blocked_ip?(addr)
      end

      # Transport seam (overridden in the unit tryout). Opens a connection PINNED
      # to validated_ip — Net::HTTP does no host lookup, it dials this exact IP —
      # while keeping the Host header and TLS SNI set to the hostname so cert
      # verification still works. Does NOT rescue timeouts: #fetch owns that
      # mapping so the real path is exercised by tests.
      def with_pinned_response(uri, validated_ip)
        http              = ::Net::HTTP.new(uri.host, uri.port)
        http.ipaddr       = validated_ip
        http.use_ssl      = true
        http.verify_mode  = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        captured = nil
        http.start do |client|
          request                                   = ::Net::HTTP::Get.new(uri.request_uri, DEFAULT_HEADERS.dup)
          client.request(request) { |resp| captured = yield resp }
        end
        captured
      end

      # Classify one response: [:redirect, location] or [:done, Result]. Reads
      # the body (capped) only for the terminal (success) case.
      def interpret_response(resp, uri, allow_html, deadline)
        code = resp.code.to_i

        if REDIRECT_CODES.include?(code)
          location = resp['location'].to_s
          raise Error, "redirect #{code} without Location header from #{uri}" if location.empty?

          return [:redirect, location]
        end

        raise Error, "unexpected HTTP status #{code} from #{uri}" unless SUCCESS_CODES.include?(code)

        body = read_capped_body(resp, deadline)
        return [:done, Result.new(body: body, content_type: resp.content_type, final_url: uri.to_s)] if allow_html

        mime = validate_image_type!(body)
        [:done, Result.new(body: body, content_type: mime, final_url: uri.to_s)]
      end

      # Enforce the byte ceiling on the declared length AND during the streamed
      # read, so a lying/absent Content-Length cannot smuggle an oversize body.
      def read_capped_body(resp, deadline)
        declared = resp.content_length
        raise ResponseTooLarge, "declared #{declared} bytes exceeds #{@max_bytes}" if declared && declared > @max_bytes

        buffer = String.new(encoding: Encoding::BINARY)
        resp.read_body do |chunk|
          check_deadline!(deadline, 'reading body') # trip a slow drip before it exhausts the buffer cap
          buffer << chunk
          raise ResponseTooLarge, "response body exceeds #{@max_bytes} bytes" if buffer.bytesize > @max_bytes
        end
        buffer
      end

      # Magic-byte validation. Rejects SVG/XML textually BEFORE sniffing (belt
      # to FastImage's :svg detection), then accepts only the sniff families
      # derived from the configured MIME allow-list. Returns the canonical MIME.
      def validate_image_type!(bytes)
        raise DisallowedContentType, 'empty response body' if bytes.empty?

        head = bytes.byteslice(0, 256).to_s
        raise DisallowedContentType, 'xml/svg payload' if head.match?(/\A\s*<(\?xml|svg)\b/i)

        type = FastImage.type(StringIO.new(bytes)) # magic-byte sniff, ignores the HTTP header
        raise DisallowedContentType, type.inspect unless @allowed_types.include?(type)

        SNIFF_CANONICAL_MIME.fetch(type)
      end

      # Resolve a redirect Location (absolute or relative) against the base URI.
      def absolutize(base_uri, location)
        URI.join(base_uri.to_s, location)
      rescue URI::InvalidURIError => ex
        raise Error, "invalid redirect Location #{location.inspect}: #{ex.message}"
      end
    end
  end
end
