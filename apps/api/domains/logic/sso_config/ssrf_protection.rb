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
      # - Blocking internal hostnames (localhost, .local, .internal)
      # - DNS rebinding protection via hostname resolution check
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

          # Block private IP ranges (when host is a literal IP)
          begin
            ip = IPAddr.new(host)

            # Check for loopback, private, or link-local addresses
            return true if ip.loopback?
            return true if ip.private?
            return true if ip.link_local?
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
        # or link-local address.
        #
        # @param hostname [String] The hostname to resolve
        # @return [Boolean] true if any resolved IP is internal
        def resolves_to_internal_ip?(hostname)
          # Resolve all A and AAAA records
          addresses = Resolv.getaddresses(hostname)

          addresses.any? do |addr_str|
            ip = IPAddr.new(addr_str)
            ip.loopback? || ip.private? || ip.link_local?
          rescue IPAddr::InvalidAddressError
            # Skip malformed addresses
            false
          end
        rescue Resolv::ResolvError, Resolv::ResolvTimeout
          # DNS resolution failed - block as a precaution
          # If we can't resolve the hostname, we shouldn't proceed
          true
        end
      end
    end
  end
end
