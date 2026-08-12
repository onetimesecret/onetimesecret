# lib/onetime/http/guard.rb
#
# frozen_string_literal: true

require 'resolv'
require 'ipaddr'

module Onetime
  module Http
    # Shared SSRF egress guard: the single source of truth for "is this IP a
    # forbidden egress target" and "resolve this host and give me addresses
    # safe to pin".
    #
    # Unifies three previously divergent per-callsite blocklists
    # (SafeFetch::BLOCKED_V4/V6, SsoConfig::SsrfProtection's
    # TRANSITION_RANGES/BLOCKED_IPV4_RANGES, and DispatchNotification's
    # loopback/private/link-local-only webhook check) into one deny-by-default,
    # fail-closed range set. Each list below is the UNION of its predecessors —
    # notably Teredo (2001::/32), which SafeFetch lacked.
    #
    # The guard is deny-by-default and fail-closed:
    #   - anything IPAddr cannot parse is BLOCKED (encoded-loopback smuggling
    #     like "2130706433" / "0x7f000001" fails closed),
    #   - a host whose RRset contains even ONE blocked address is rejected
    #     wholesale (defeats one-public-one-private split RRsets),
    #   - empty resolution is rejected (nothing resolvable, nothing fetchable).
    #
    # Callers that dial the returned addresses should pin the connection to one
    # exact validated IP (e.g. Net::HTTP#ipaddr=) so no second DNS resolution
    # happens at connect time — closing the classic validate-then-reresolve
    # (DNS-rebinding) window. See SafeFetch for the canonical pinned-dial
    # implementation.
    module Guard
      # Raised when a host/address is a forbidden egress target (blocked
      # range, unparseable address, or empty resolution).
      class Blocked < Onetime::Problem; end

      # Deny-by-default range lists. A resolved IP is blocked unless it
      # belongs to NONE of these. v4-mapped and v4-compatible IPv6 are
      # unwrapped to their v4 form first (see #blocked_ip?).
      BLOCKED_V4 = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
        172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
        224.0.0.0/4 240.0.0.0/4
      ].map { |cidr| IPAddr.new(cidr) }.freeze
      # 0.0.0.0/8      "this host on this network" (RFC 1122; 0.0.0.0
      #                connects to localhost on Linux — a loopback bypass the
      #                native IPAddr predicates miss)
      # 100.64.0.0/10  CGNAT / shared address space (RFC 6598)
      # 192.0.0.0/24   IETF protocol assignments (RFC 6890)
      # 198.18.0.0/15  benchmarking (RFC 2544)
      # 224.0.0.0/4    multicast
      # 240.0.0.0/4    reserved + 255.255.255.255 broadcast

      # ::/96 is the deprecated IPv4-compatible block (subsumes ::, ::1, and
      # e.g. ::127.0.0.1). The IPv6 transition prefixes — 2002::/16 (6to4),
      # the 64:ff9b* NAT64 ranges, and 2001::/32 (Teredo, RFC 4380) — all
      # embed a routable IPv4 destination the native IPAddr predicates never
      # look at; they are blocked wholesale because no legitimate egress
      # target lives on a translation address, and decoding-then-allowing
      # would just reintroduce the bypass surface we are trying to close.
      # ::ffff:0:0/96 is the separate v4-MAPPED block (unwrapped to v4 in
      # #blocked_ip?, listed here as a belt).
      BLOCKED_V6 = %w[
        ::/96 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96
        64:ff9b::/96 64:ff9b:1::/48 2001::/32 2002::/16 2001:db8::/32
      ].map { |cidr| IPAddr.new(cidr) }.freeze

      # extend self (rather than module_function) keeps every method callable
      # both as Guard.blocked_ip?(...) and as an instance method for classes
      # that `include Guard`. The DNS seam stays stubbable in tests by
      # redefining the singleton method (def Guard.resolve_addresses).
      extend self

      # Deny-by-default IP check. Accepts a String or IPAddr. Fails closed on
      # anything IPAddr cannot parse — notably Ruby's IPAddr rejects
      # decimal/octal/hex-encoded forms (e.g. "2130706433", "0x7f000001")
      # with InvalidAddressError, so such loopback-smuggling attempts are
      # treated as blocked rather than resolved.
      #
      # @param addr [String, IPAddr]
      # @return [Boolean] true if the address is a forbidden egress target
      def blocked_ip?(addr)
        ip = addr.is_a?(IPAddr) ? addr : IPAddr.new(addr.to_s)
        # Unwrap IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible (::a.b.c.d)
        # IPv6 to the embedded IPv4 so the v4 range list actually sees it.
        # #native returns the address unchanged when it is neither, so this
        # is safe for all IPs.
        ip = ip.native if ip.ipv6? && (ip.ipv4_mapped? || ip.ipv4_compat?)

        # Unspecified address in either family (0.0.0.0, :: — including the
        # ::0.0.0.0 spelling, which is not ipv4_compat? so the unwrap above
        # leaves it as ::). Both route to localhost as a connect target.
        return true if ip.to_i.zero?

        # 169.254.0.0/16 and fe80::/10 are already in BLOCKED_V4/BLOCKED_V6;
        # this is a redundant early-out on IPAddr's own predicate, not extra
        # coverage.
        return true if ip.link_local?

        (ip.ipv4? ? BLOCKED_V4 : BLOCKED_V6).any? { |net| net.include?(ip) }
      rescue IPAddr::InvalidAddressError
        true # fail closed
      end

      # Resolve host A + AAAA, validate EVERY address, and fail closed: raise
      # if ANY resolved address is blocked (defeats one-public-one-private
      # RRsets). Returns ALL validated addresses uniq'd and ordered
      # IPv4-first: resolvers commonly list AAAA ahead of A, and a machine
      # with an IPv6 address but no IPv6 route (broken dual-stack) would
      # otherwise dial an unreachable v6 and never try a perfectly good v4.
      #
      # IP-literal hosts: Resolv::DNS#getaddresses returns [] for a literal
      # (it speaks only DNS; the generic Resolv.getaddresses handles literals
      # via the hosts resolver, which we deliberately avoid), so a literal
      # host is validated directly and returned as-is.
      #
      # @param host [String] hostname or IP literal
      # @return [Array<String>] validated addresses, IPv4-first
      # @raise [Blocked]
      def resolve_and_validate!(host)
        addrs = resolve_addresses(host)
        addrs = [host] if addrs.empty? && ip_literal?(host)
        raise Blocked, "no A/AAAA records for #{host}" if addrs.empty?

        addrs.each do |addr|
          raise Blocked, "blocked address #{addr} for #{host}" if blocked_ip?(addr)
        end

        # Safe to parse: anything unparseable already failed closed in blocked_ip?.
        v4, v6 = addrs.uniq.partition { |addr| IPAddr.new(addr).ipv4? }
        v4 + v6
      end

      # The single address a caller should pin its connection to.
      #
      # @param host [String]
      # @return [String] the first validated address (IPv4 preferred)
      # @raise [Blocked]
      def pinned_address!(host)
        resolve_and_validate!(host).first
      end

      # Isolated for testability (redefined in the unit tryout to avoid real
      # DNS). Returns an array of IP strings (both families).
      def resolve_addresses(host)
        ::Resolv::DNS.open { |dns| dns.getaddresses(host).map(&:to_s) }
      end

      # @return [Boolean] true if host parses as an IP address literal
      #   (IPAddr also accepts the bracketed IPv6 form URI#host returns,
      #   e.g. "[::1]")
      def ip_literal?(host)
        IPAddr.new(host.to_s)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end
end
