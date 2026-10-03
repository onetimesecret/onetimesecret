# lib/middleware/detect_host.rb
#
# frozen_string_literal: true

require 'ipaddr'
require 'otto/env_keys'
require 'rack/utils'
require_relative 'logging'

module Rack
  # Middleware to accurately detect the client's host in a Rack application.
  #
  # This middleware examines incoming HTTP requests and attempts to determine
  # the correct host by inspecting a prioritized list of HTTP headers. While
  # Rack's default `req.host` method provides basic host detection using the
  # `Host` header, this middleware extends that functionality by considering
  # additional headers that are commonly set by proxies and load balancers.
  #
  # ### Rationale
  #
  # In environments where the application is behind reverse proxies, load
  # balancers, or CDN services (like AWS ALB, nginx, or CloudFlare), the
  # client-requested host may be forwarded in `X-Forwarded-Host`. Rack does
  # not trust that header by default, as it can be set by clients.
  #
  # However, in controlled environments where the header is set by trusted
  # infrastructure components, it's necessary to respect it to accurately
  # determine the host for proper URL generation, redirection, and
  # processing in multi-tenant applications.
  #
  # ### The reverse-proxy authority contract (#4384)
  #
  # The application reads the request authority from exactly two places
  # (mirroring HEADER_PRECEDENCE below):
  #
  # 1. `X-Forwarded-Host` - only from a trusted proxy (see Security
  #    Considerations), and only when it carries a single value.
  # 2. `Host` - the direct/default authority.
  #
  # The proxy in front of the application adapts everything else to that:
  # it overwrites `X-Forwarded-Host` with the host the browser asked for
  # whenever it rewrites `Host`, never appends to or passes through a
  # client-supplied value, and removes the other carriers
  # (`Apx-Incoming-Host`, `X-Original-Host`, RFC 7239 `Forwarded`) before
  # the request reaches the application. See docs/operations/
  # proxy-authority-header.md.
  #
  # A comma-separated `X-Forwarded-Host` is not a chain to pick from under
  # an overwrite-only contract. It is skipped with a WARN and detection
  # continues with `Host`.
  #
  # The other carriers never supply the detected host. They are still
  # OBSERVED, so the admin-surface provenance rule can keep declining a
  # request whose edge rewrote `Host` and carried the public host somewhere
  # this middleware does not read:
  #
  # - the first `host=` of RFC 7239 `Forwarded` is published to
  #   `env[rfc7239_host_field_name]` (see `.rfc7239_host`);
  # - the hosts named by `Apx-Incoming-Host`, `X-Original-Host`, and the
  #   first value of a skipped multi-valued `X-Forwarded-Host` are published
  #   to `env[unselected_hosts_field_name]` (see `.unselected_hosts`).
  #
  # It also includes validation to filter out invalid or local hosts (e.g.,
  # `localhost`, `127.0.0.1`) and IP addresses, ensuring only legitimate
  # external hosts are considered.
  #
  # ### Configuration
  #
  # The middleware allows setting a class-level `result_field_name` variable,
  # which can be initialized from an environment variable `DETECTED_HOST`.
  #
  # ```ruby
  # Rack::DetectHost.result_field_name = ENV['DETECTED_HOST'] || 'default_host_value'
  # ```
  #
  # ### Usage
  #
  # Use this middleware in your Rack-based application by inserting it into
  # the middleware stack:
  #
  # ```ruby
  # use Rack::DetectHost
  # ```
  #
  # After the middleware processes a request, it sets `env['rack.detected_host']`
  # with the determined host value, which can be used downstream in your
  # application for routing or generating URLs.
  #
  # ### Security Considerations
  #
  # **Trusted Proxy Validation**: This middleware only trusts
  # X-Forwarded-Host when the request arrived via a trusted reverse proxy.
  # The otto trust key
  # is TRI-STATE (otto#228) and, when present, authoritative in BOTH
  # directions:
  #
  # - env['otto.via_trusted_proxy'] PRESENT — recorded by Otto's
  #   IPPrivacyMiddleware (mounted earlier in the stack) from the ORIGINAL
  #   connecting peer, before it rewrites REMOTE_ADDR to the resolved client
  #   IP, and only when the operator configured proxy trust. true = the peer
  #   matched a trusted-proxy CIDR (filter mode) or count-based depth mode
  #   is active (configuring a depth asserts the peer is the proxy tier;
  #   otto#226). false = trust IS configured and the peer failed it — an
  #   authoritative deny; the heuristic below does not apply.
  # - Key ABSENT — no proxy trust configured (or the otto middleware is not
  #   mounted). Only then does the legacy heuristic apply: a private/
  #   loopback REMOTE_ADDR grants trust, keeping self-hosted installs behind
  #   a local reverse proxy working without any trusted-proxy config.
  #
  # A present-but-non-boolean value (a future otto surprise) is treated as
  # untrusted rather than falling through to the heuristic: presence implies
  # the authoritative contract. Direct requests from public IPs can only use
  # the Host header.
  #
  # This prevents header spoofing attacks where malicious clients set
  # X-Forwarded-Host to impersonate different hosts.
  #
  # ### Note on Rack's Default Behavior
  #
  # While Rack's `request.host` method provides basic host detection using
  # the `Host` header, it does not, by default, consider `X-Forwarded-Host`
  # unless explicitly configured. This middleware adds that, which is
  # needed in proxy and load-balanced environments where the original host
  # is forwarded by trusted components.
  #
  class DetectHost
    include Middleware::Logging

    # NOTE: CF-Visitor header only contains scheme information { "scheme": "https" }
    # and is not used for host detection
    unless defined?(HEADER_PRECEDENCE)
      # Forwarded headers that require trusted proxy validation.
      # These headers can be spoofed by clients and are only trusted when
      # otto's tri-state key grants it (otto.via_trusted_proxy == true) or,
      # with the key absent (no proxy trust configured), when REMOTE_ADDR is
      # a private/loopback address — see the trust decision in #call.
      # Every header listed here is an implicit contract with the proxy
      # tier: the trusted-proxy gate assumes the proxy overwrites or strips
      # it, so an entry the proxy doesn't manage is one a client can set
      # THROUGH trusted infra. The list is one header (#4384) because it is
      # the one every other layer already keys on: otto's
      # IPPrivacyMiddleware deletes it from a peer that fails configured
      # proxy trust, StripForwardedHost deletes it before any app reads
      # request.host, and Rack::Request#forwarded_authority reads it.
      # Vendor carriers (Apx-Incoming-Host, X-Original-Host), the IIS
      # originals (X-Original-URL, X-Rewrite-URL), X-Forwarded-Server
      # (names the proxy itself) and RFC 7239 Forwarded are translated or
      # removed at the edge. Scheme-only headers (X-Forwarded-Proto,
      # CF-Visitor, ...) don't belong here either: this middleware detects
      # hosts, not schemes.
      FORWARDED_HEADERS = [
        'X-Forwarded-Host',
      ].freeze

      # Carriers this middleware read before #4384 and no longer selects.
      # They are observed only (see .unselected_hosts): a value that still
      # arrives here means the edge did not translate or remove it.
      UNSELECTED_HOST_HEADERS = [
        'Apx-Incoming-Host',  # Approximated custom-domain ingress
        'X-Original-Host',    # Various proxy services
      ].freeze

      # List of HTTP headers that might contain the host, in order of precedence.
      # Headers earlier in the list are given priority over later ones.
      # NOTE: FORWARDED_HEADERS are only checked when request comes from trusted proxy.
      HEADER_PRECEDENCE = (FORWARDED_HEADERS + ['Host']).freeze

      # Hostnames and IP addresses that should never be accepted as valid hosts.
      # These typically indicate local or development environments.
      INVALID_HOSTS = [
        'localhost',
        'localhost.localdomain',
        '127.0.0.1',
        '::1',
      ].freeze

      # Rack env key written by Otto's IPPrivacyMiddleware. Referenced from
      # Otto::EnvKeys so a rename upstream has exactly one surface to update
      # (previously a duplicated literal pinned by a tryout).
      VIA_TRUSTED_PROXY_KEY = Otto::EnvKeys::VIA_TRUSTED_PROXY
    end

    # Class-level setting initialized from ENV variable
    @result_field_name = ENV['DETECTED_HOST'] || 'rack.detected_host'

    class << self
      attr_accessor :result_field_name

      # Validated `host:port` authority for the selected, trusted
      # X-Forwarded-Host. The port is the one that header carries or, when
      # it is a bare hostname, the single-valued X-Forwarded-Port sent with
      # it. Never populated from Host or observed carriers, and absent when
      # X-Forwarded-Host was not the selected header.
      def forwarded_authority_field_name
        "#{result_field_name}.forwarded_authority"
      end

      # Env key under which the observed RFC 7239 `host=` is published — a
      # sidecar of result_field_name, so a renamed result field carries its
      # observation with it. Absent when the request has no readable, valid
      # `host=`.
      #
      # @return [String]
      def rfc7239_host_field_name
        "#{result_field_name}.rfc7239_host"
      end

      # Env key under which the hosts named by carriers this middleware
      # does not select are published — a sidecar of result_field_name,
      # like rfc7239_host_field_name. Absent when there are none.
      #
      # @return [String]
      def unselected_hosts_field_name
        "#{result_field_name}.unselected_hosts"
      end
    end

    # Initializes the middleware with the application and logging options.
    #
    # @param app [#call] The Rack application
    # @param logger [Logger, nil] Optional logger instance to use
    # @return [void]
    def initialize(app, logger: nil)
      @app           = app
      @custom_logger = logger
    end

    # Override logger to allow custom logger injection
    def logger
      @custom_logger || super
    end

    # Processes the request and determines the appropriate host.
    #
    # @param env [Hash] Rack environment hash
    # @return [Array] Standard Rack response array from the next middleware
    #
    # This method:
    # 1. Determines if request is from a trusted proxy (otto's trusted-proxy
    #    signal, or a private/loopback REMOTE_ADDR)
    # 2. Examines headers in order of precedence (X-Forwarded-Host only from
    #    trusted proxies, and only when single-valued)
    # 3. Normalizes and validates each potential host
    # 4. Accepts the first valid host found
    # 5. Stores the result in env[result_field_name]
    # 6. Publishes what the unselected carriers named, for the admin gate
    # 7. Passes the request to the next middleware
    def call(env)
      result_field_name = self.class.result_field_name
      detected_host     = nil
      env.delete(self.class.forwarded_authority_field_name)

      # Determine which headers to check based on whether request comes from
      # a trusted proxy. Forwarded headers can be spoofed by clients, so they
      # are only honored for requests that arrived via trusted infrastructure.
      #
      # The otto key is tri-state (otto#228); a PRESENT key is authoritative
      # in both directions and the heuristic applies only when it is absent:
      #
      # a. Key present: otto's IPPrivacyMiddleware (mounted earlier in the
      #    stack) recorded it from the ORIGINAL connecting peer — before
      #    rewriting REMOTE_ADDR to the resolved client IP — and only
      #    because the operator configured proxy trust (CIDR matchers, or a
      #    depth: otto#226 grants depth-mode peer trust; the otto#151 remap
      #    was dropped, so extra leftmost XFF entries never shift the
      #    right-anchored selection; a chain shorter than the depth falls
      #    back to the peer, and a depth larger than the real hop count
      #    selects a client-supplied entry — each hop must append exactly
      #    one entry and the origin must stay unreachable except through
      #    the proxy tier). After the rewrite REMOTE_ADDR no
      #    longer identifies the peer — with proxy trust enabled it holds
      #    the real (public) visitor IP, so re-checking it here would
      #    wrongly discard forwarded host headers and fail every custom
      #    domain to canonical (2026-08-05 incident). A false key means the
      #    configured trust REJECTED this peer — honoring the private-IP
      #    heuristic anyway would let any request that resolves to a
      #    private REMOTE_ADDR bypass the operator's explicit trust
      #    decision. A present-but-non-boolean value (a future otto
      #    surprise) is treated as untrusted: presence implies the
      #    authoritative contract.
      # b. Key absent: no proxy trust configured, or the otto middleware is
      #    not mounted (bare-Rack stacks). Only here does the legacy
      #    heuristic apply: a private/loopback REMOTE_ADDR grants trust,
      #    keeping default-config self-hosted installs behind a local
      #    reverse proxy (nginx/Caddy on the same box or LAN) working.
      remote_addr        = env['REMOTE_ADDR']
      from_trusted_proxy = self.class.from_trusted_proxy?(env)

      headers_to_check = if from_trusted_proxy
        HEADER_PRECEDENCE
      else
        # Untrusted source: only the Host header is honored.
        log_untrusted_request(env, remote_addr)
        ['Host']
      end

      # Try headers in order of precedence
      headers_to_check.each do |header|
        header_key = self.class.env_key(header)

        # Overwrite-only contract: more than one X-Forwarded-Host value is
        # a proxy that appended instead of overwriting. Neither value is
        # selected; detection continues with Host.
        if header != 'Host' && self.class.multi_valued?(env[header_key])
          logger.warn(
            "[DetectHost] Ignoring #{header} with #{self.class.value_count(env[header_key])} values; " \
            'the proxy must overwrite it with a single host. Falling back to Host',
          )
          next
        end

        host = self.class.normalize_host(env[header_key])
        next if host.nil?

        if self.class.valid_domain_name?(host)
          detected_host = host
          if header == 'X-Forwarded-Host'
            authority                                      = self.class.forwarded_authority(
              env[header_key], host, env[self.class.env_key('X-Forwarded-Port')]
            )
            env[self.class.forwarded_authority_field_name] = authority if authority
          end
          logger.debug("[DetectHost] #{host} via #{header_key}")
          break # stop on first valid host
        elsif self.class.private_ip?(host)
          logger.debug("[DetectHost] Private IP address #{host} via #{header_key}")
        elsif self.class.valid_ip?(host)
          logger.warn("[DetectHost] External IP address #{host} via #{header_key}")
        else
          logger.debug("[DetectHost] Invalid host detected #{host} via #{header_key}")
        end
      end

      # Log indication if no valid host found in debug mode
      unless detected_host
        logger.debug('[DetectHost] No valid host detected in request')
      end

      # e.g. env['rack.detected_host'] = 'example.com'
      env[result_field_name] = detected_host

      # Observation only, never a source (see the class doc): what RFC 7239
      # Forwarded ASSERTS the host is, published for the admin-surface
      # provenance rule regardless of peer trust — trust is that rule's
      # decision, not this one's.
      rfc7239_host                            = self.class.rfc7239_host(env['HTTP_FORWARDED'])
      env[self.class.rfc7239_host_field_name] = rfc7239_host if rfc7239_host

      # Same for the carriers dropped from the precedence list in #4384.
      unselected                                  = self.class.unselected_hosts(env)
      env[self.class.unselected_hosts_field_name] = unselected unless unselected.empty?

      @app.call(env)
    end

    private

    # Logs why forwarded host headers are being ignored for this request,
    # stating the actual trust inputs (the otto key's presence/value and the
    # private_ip? result). REMOTE_ADDR is labeled post-proxy-resolution: by
    # the time this middleware runs, IPPrivacyMiddleware may have rewritten
    # it, so it does not necessarily identify the connecting peer.
    #
    # Logs at WARN when X-Forwarded-Host is discarded: a proxy that is not
    # recognised as trusted is the signature of the 2026-08-05 incident
    # (custom domains falling back to canonical). With proxy trust
    # configured, otto removes the header from a peer that fails it before
    # this middleware runs, so this line appears only in the unconfigured
    # (private-peer heuristic) mode; otto's own log is the signal otherwise.
    #
    # @param env [Hash] Rack environment hash
    # @param remote_addr [String, nil] env['REMOTE_ADDR'] after any rewrite
    # @return [void]
    def log_untrusted_request(env, remote_addr)
      via_key      = env.key?(VIA_TRUSTED_PROXY_KEY) ? env[VIA_TRUSTED_PROXY_KEY].inspect : 'absent'
      trust_inputs = "#{VIA_TRUSTED_PROXY_KEY}=#{via_key}, " \
                     "private_ip=#{self.class.private_ip?(remote_addr)}, " \
                     "remote_addr=#{remote_addr} (post-proxy-resolution)"

      discarded    = FORWARDED_HEADERS.select { |header| env.key?(self.class.env_key(header)) }

      if discarded.empty?
        logger.debug("[DetectHost] Untrusted source, no forwarded host headers present (#{trust_inputs})")
      else
        logger.warn(
          "[DetectHost] Discarding forwarded host headers (#{discarded.join(', ')}) " \
          'from untrusted source; if this peer is your reverse proxy, custom domains ' \
          "are resolving on Host — configure site.network.trusted_proxy (#{trust_inputs})",
        )
      end
    end

    module ClassMethods
      # Extracts and normalizes the host from a header value.
      #
      # @param value_unsafe [String, nil] Raw header value from the request
      # @return [String, nil] Normalized host without port number, or nil if empty
      #
      # Takes the first host if multiple are provided (comma-separated), then
      # delegates port stripping and normalization to DomainParser. #call
      # never selects from a multi-valued X-Forwarded-Host (see
      # .multi_valued?); the first-value read remains for Host and for the
      # observations.
      def normalize_host(value_unsafe)
        first_host = value_unsafe.to_s.split(',').first.to_s

        Onetime::Utils::DomainParser.extract_hostname(first_host)
      end

      # Whether forwarded headers on this request came from trusted
      # infrastructure: otto's verdict when it recorded one, the
      # private/loopback-peer heuristic otherwise. See the trust decision in
      # #call. Shared with StripForwardedHost so the host and the port are
      # trusted on one verdict.
      #
      # @param env [Hash] Rack environment
      # @return [Boolean]
      def from_trusted_proxy?(env)
        if env.key?(VIA_TRUSTED_PROXY_KEY)
          env[VIA_TRUSTED_PROXY_KEY] == true
        else
          private_ip?(env['REMOTE_ADDR'])
        end
      end

      # Retain only a plain DNS authority with a usable port. Host detection
      # is deliberately more permissive (e.g. URL extraction); do not carry
      # that extra syntax into the rewritten HTTP_HOST.
      #
      # The port in the value itself wins. A bare hostname takes the port
      # from +forwarded_port+ (X-Forwarded-Port) when that is one numeric
      # value: the common proxy setup sends the hostname and the port in
      # separate headers. A port written in the value that is unusable is
      # not replaced, and a list of ports is not picked from.
      def forwarded_authority(value, host, forwarded_port = nil)
        match = value.to_s.strip.match(/\A([a-z0-9.-]+)(?::([0-9]{1,5}))?\z/i)
        return nil unless match && normalize_host(match[1]) == host

        port = (match[2] || forwarded_port.to_s.strip[/\A[0-9]{1,5}\z/]).to_i
        return nil unless (1..65_535).cover?(port)

        "#{host}:#{port}"
      end

      # Rack env key for an HTTP header name.
      #
      # @param header [String] e.g. 'X-Forwarded-Host'
      # @return [String] e.g. 'HTTP_X_FORWARDED_HOST'
      def env_key(header)
        "HTTP_#{header.tr('-', '_').upcase}"
      end

      # Whether a header value carries more than one entry. A repeated
      # header reaches Rack comma-joined, the same shape as a proxy that
      # appended, so both count.
      #
      # @param value_unsafe [String, nil] Raw header value
      # @return [Boolean]
      def multi_valued?(value_unsafe)
        value_unsafe.to_s.include?(',')
      end

      # How many comma-separated entries a header value carries, counting
      # empty ones.
      #
      # @param value_unsafe [String, nil] Raw header value
      # @return [Integer]
      def value_count(value_unsafe)
        value_unsafe.to_s.split(',', -1).size
      end

      # The hosts named by carriers this middleware does not select:
      # UNSELECTED_HOST_HEADERS, and the first value of a multi-valued
      # X-Forwarded-Host. Each is normalized and validated exactly as a
      # forwarded host header would be; anything that fails is no
      # observation. Read regardless of peer trust — what to make of them
      # is the admin-surface provenance rule's decision.
      #
      # @param env [Hash] Rack environment hash
      # @return [Array<String>] distinct hosts, frozen; empty when none
      def unselected_hosts(env)
        values  = UNSELECTED_HOST_HEADERS.map { |header| env[env_key(header)] }
        FORWARDED_HEADERS.each do |header|
          value = env[env_key(header)]
          values << value if multi_valued?(value)
        end

        values.filter_map do |value|
          host = normalize_host(value)
          host if host && valid_domain_name?(host)
        end.uniq.freeze
      end

      # The host an RFC 7239 Forwarded value asserts, or nil.
      #
      # @param value_unsafe [String, nil] Raw Forwarded header value
      # @return [String, nil] The first `host=` parameter, normalized and
      #   validated exactly as a forwarded host header would be, or nil when
      #   there is none, Rack's parser rejects the value as malformed, or the
      #   host would not have been accepted from any forwarded header (an IP
      #   literal, localhost, a malformed name)
      #
      # Parsing is delegated to Rack::Utils.forwarded_values, which handles
      # quoted strings and escape sequences, bounds parameter and escape
      # counts against denial of service, and returns an empty hash on
      # malformed input. Element boundaries are flattened: the earliest
      # `host=` anywhere in the header wins, mirroring the first-value
      # convention used for X-Forwarded-Host.
      def rfc7239_host(value_unsafe)
        return nil if value_unsafe.nil?

        first = case Rack::Utils.forwarded_values(value_unsafe)
                in { host: [first_host, *] }
                  first_host
                else
                  nil
                end
        host  = normalize_host(first)
        return nil if host.nil? || !valid_domain_name?(host)

        host
      end

      # Determines if a string is a valid host for use in this application.
      #
      # @param host [String] The host to validate
      # @return [Boolean] true if the host is a valid domain name
      #
      # Note: This method intentionally rejects IP addresses as we require
      # domain names for our application's routing logic. It also requires
      # DomainParser.basically_valid? (RFC 952/1123 charset, label and
      # length limits) so header junk that survives extraction — control
      # characters, quotes, semicolons — can never become the detected
      # host. DomainStrategy applies the same gate after extraction.
      def valid_domain_name?(host)
        return false if INVALID_HOSTS.include?(host)
        return false if valid_ip?(host)

        Onetime::Utils::DomainParser.basically_valid?(host)
      end

      # Determines if a string represents a private IP address.
      #
      # @param ip_string [String, nil] String to check
      # @return [Boolean] true if the string is a valid private IP address
      #
      # Checks for:
      # - IPv4 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
      # - IPv4 loopback addresses (127.0.0.0/8)
      # - IPv6 unique local addresses (fc00::/7)
      # - IPv6 link-local addresses (fe80::/10)
      # - IPv6 loopback address (::1/128)
      def private_ip?(ip_string)
        return false if ip_string.to_s.empty?

        ip = IPAddr.new(ip_string)

        # Check for private IPv4 ranges (RFC 1918)
        if ip.ipv4?
          return ip.private? || ip.loopback?

        # Check for private IPv6 ranges
        elsif ip.ipv6?
          fc00     = IPAddr.new('fc00::/7')
          fe80     = IPAddr.new('fe80::/10')
          loopback = IPAddr.new('::1/128')

          return fc00.include?(ip) || # Unique Local Addresses
                 fe80.include?(ip) || # Link-local addresses
                 loopback.include?(ip) # Loopback
        end

        false
      rescue IPAddr::InvalidAddressError
        false
      end

      # Determines if a string represents a valid IP address.
      #
      # @param ip_string [String] String to check
      # @return [Boolean] true if the string is a valid IP address
      def valid_ip?(ip_string)
        return false if ip_string.to_s.empty?

        IPAddr.new(ip_string)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end

    extend ClassMethods
  end
end
