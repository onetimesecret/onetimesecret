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
      # IP range coverage (transition prefixes, special-use IPv4, multicast,
      # documentation ranges, etc.) lives in Onetime::Http::Guard — the shared
      # SSRF egress guard and single source of truth for "is this IP a
      # forbidden egress target". blocked_ip? below delegates to it.
      #
      # Note on DNS rebinding: While we resolve hostnames at validation time,
      # a sophisticated attacker could still exploit DNS rebinding by returning
      # a safe IP during our check, then switching to an internal IP during
      # the actual OmniAuth request (if sufficient time passes). Request-time
      # DNS pinning is now implemented at the HTTP-client callsites (SafeFetch,
      # webhook dispatch, SSO test connection, and the OIDC Faraday hook), so
      # the validation here is defense-in-depth, not the only line.
      #
      # Usage:
      #   include SsrfProtection
      #   # Then call valid_issuer_host?(url) to validate
      #
      module SsrfProtection
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
        # Returns true if the hostname resolves to any address the shared
        # egress guard forbids (loopback, private, link-local, transition
        # prefixes, multicast, etc.). A resolver answer we cannot parse also
        # counts as internal: Guard.blocked_ip? fails closed on unparseable
        # input, so malformed addresses block rather than being skipped.
        # Empty resolution (NXDOMAIN / no A/AAAA records) also counts as
        # internal — an unresolvable host is not a valid egress target.
        #
        # @param hostname [String] The hostname to resolve
        # @return [Boolean] true if any resolved IP is internal
        def resolves_to_internal_ip?(hostname)
          # Resolve all A and AAAA records
          addresses = Resolv.getaddresses(hostname)

          # Fail closed on empty resolution. Resolv.getaddresses returns []
          # (rather than raising) for NXDOMAIN or a host with no A/AAAA
          # records, so without this an unresolvable issuer host would slip
          # through save-time validation as "not internal". A host that
          # resolves to nothing is not a valid egress target; the request-time
          # guard (Guard.resolve_and_validate!) already rejects empty
          # resolution, and this keeps save-time consistent with it.
          return true if addresses.empty?

          addresses.any? { |addr_str| blocked_ip?(addr_str) }
        rescue Resolv::ResolvError, Resolv::ResolvTimeout
          # DNS resolution failed - block as a precaution
          # If we can't resolve the hostname, we shouldn't proceed
          true
        end

        # Determines whether an IP address points at an internal/private
        # destination. Thin delegation to the shared egress guard, which
        # unwraps IPv4-embedded IPv6 forms, blocks transition prefixes, and
        # fails closed (returns true) on anything IPAddr cannot parse.
        #
        # @param ip [IPAddr, String] The address to check
        # @return [Boolean] true if the address is internal/blocked
        def blocked_ip?(ip)
          Onetime::Http::Guard.blocked_ip?(ip)
        end
      end
    end
  end
end
