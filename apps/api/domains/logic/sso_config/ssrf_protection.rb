# apps/api/domains/logic/sso_config/ssrf_protection.rb
#
# frozen_string_literal: true

require 'uri'
require 'ipaddr'
require 'resolv'

module DomainsAPI
  module Logic
    module SsoConfig
      # SSRF Protection for Domain SSO Configuration URLs
      #
      # This module provides validation methods to prevent Server-Side Request
      # Forgery (SSRF) attacks when processing issuer URLs. OmniAuth OIDC
      # discovery fetches metadata from the issuer URL, so we must validate
      # that the URL does not point to internal/private networks.
      #
      # Protection includes:
      # - Blocking literal internal IPs (loopback, private, link-local)
      # - Unwrapping IPv4-mapped IPv6 literals and re-checking the embedded IPv4
      # - Blocking IPv6 transition ranges (NAT64, 6to4, Teredo) wholesale
      # - Blocking internal hostnames (localhost, .local, .internal)
      # - DNS rebinding protection via hostname resolution check
      #
      # Note on IPv6 transition addresses: Ruby's IPAddr#loopback?, #private?,
      # and #link_local? only match native IPv4/IPv6 ranges. They do NOT look at
      # IPv4 addresses embedded in IPv6 transition formats, so an address like
      # ::ffff:169.254.169.254 (IPv4-mapped) or 64:ff9b::a9fe:a9fe (NAT64) would
      # otherwise slip past the guard. blocked_ip? closes that gap by unwrapping
      # IPv4-mapped literals to their embedded IPv4 and by blocking the transition
      # prefixes outright, since no legitimate SSO issuer resolves into them.
      #
      # Note on DNS rebinding: While we resolve hostnames at validation time,
      # a sophisticated attacker could still exploit DNS rebinding by returning
      # a safe IP during our check, then switching to an internal IP during
      # the actual OmniAuth request (if sufficient time passes). Full mitigation
      # would require DNS pinning at the HTTP client level, which is beyond
      # the scope of this module.
      #
      # Usage:
      #   include SsrfProtection
      #   # Then call valid_issuer_host?(url) to validate
      #
      module SsrfProtection
        # IPv6 transition prefixes that embed a routable IPv4 destination.
        # These are blocked wholesale: an SSO issuer has no legitimate reason
        # to resolve into any of them, and decoding-then-allowing would just
        # reintroduce the bypass surface we are trying to close.
        TRANSITION_RANGES = [
          IPAddr.new('2001::/32'),      # Teredo (RFC 4380)
          IPAddr.new('2002::/16'),      # 6to4 (RFC 3056)
          IPAddr.new('64:ff9b::/96'),   # NAT64 well-known prefix (RFC 6052)
          IPAddr.new('64:ff9b:1::/48'), # NAT64 local-use prefix (RFC 8215)
        ].freeze

        # Validates that a URL host is safe for external requests.
        #
        # @param url [String] The URL to validate
        # @return [Boolean] true if the host is safe, false otherwise
        def valid_issuer_host?(url)
          uri = URI.parse(url)

          # Must be HTTPS
          return false unless uri.scheme == 'https'

          # Must have a host
          return false if uri.host.nil? || uri.host.empty?

          # Prevent localhost/internal IPs (SSRF)
          return false if internal_host?(uri.host)

          true
        rescue URI::InvalidURIError
          false
        end

        # Checks if a host resolves to an internal/private address.
        #
        # @param host [String] The hostname or IP address to check
        # @return [Boolean] true if the host is internal/private, false otherwise
        def internal_host?(host)
          # Block localhost and common internal hostnames
          return true if host == 'localhost'
          return true if host.end_with?('.local')
          return true if host.end_with?('.internal')

          # Block private IP ranges (when host is a literal IP). IPAddr accepts
          # the bracketed IPv6 form that URI#host returns (e.g. "[::1]").
          begin
            ip = IPAddr.new(host)
            return true if blocked_ip?(ip)
          rescue IPAddr::InvalidAddressError
            # Not an IP address, continue to DNS resolution check
          end

          # DNS rebinding protection: resolve hostname and check all IPs
          # This prevents bypasses like 127.0.0.1.nip.io or localtest.me
          return true if resolves_to_internal_ip?(host)

          false
        end

        # Resolves a hostname and checks if any resolved IP is internal.
        #
        # Returns true if the hostname resolves to a loopback, private,
        # link-local, or IPv6-transition address.
        #
        # @param hostname [String] The hostname to resolve
        # @return [Boolean] true if any resolved IP is internal
        def resolves_to_internal_ip?(hostname)
          # Resolve all A and AAAA records
          addresses = Resolv.getaddresses(hostname)

          addresses.any? do |addr_str|
            blocked_ip?(IPAddr.new(addr_str))
          rescue IPAddr::InvalidAddressError
            # Skip malformed addresses
            false
          end
        rescue Resolv::ResolvError, Resolv::ResolvTimeout
          # DNS resolution failed - block as a precaution
          # If we can't resolve the hostname, we shouldn't proceed
          true
        end

        # Determines whether an IP address points at an internal/private
        # destination, accounting for IPv6 transition formats.
        #
        # @param ip [IPAddr] The address to check
        # @return [Boolean] true if the address is internal/blocked
        def blocked_ip?(ip)
          # Unwrap IPv4-mapped IPv6 (::ffff:a.b.c.d) to the embedded IPv4 so the
          # native range predicates below actually see it. #native returns the
          # address unchanged when it is not mapped, so this is safe for all IPs.
          ip = ip.native if ip.ipv6? && ip.ipv4_mapped?

          return true if ip.loopback?
          return true if ip.private?
          return true if ip.link_local?

          # NAT64 / 6to4 / Teredo carry an embedded IPv4 the native predicates
          # ignore. Block the whole prefixes rather than decode-and-allow.
          return true if ip.ipv6? && TRANSITION_RANGES.any? { |range| range.include?(ip) }

          false
        end
      end
    end
  end
end
