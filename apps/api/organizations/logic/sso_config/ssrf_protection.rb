# apps/api/organizations/logic/sso_config/ssrf_protection.rb
#
# frozen_string_literal: true

require 'uri'
require 'ipaddr'

module OrganizationAPI::Logic
  module SsoConfig
    # SSRF Protection for SSO Configuration URLs
    #
    # This module provides validation methods to prevent Server-Side Request
    # Forgery (SSRF) attacks when processing issuer URLs. OmniAuth OIDC
    # discovery fetches metadata from the issuer URL, so we must validate
    # that the URL does not point to internal/private networks.
    #
    # Limitations:
    # - DNS rebinding attacks are NOT prevented. The URL is validated at parse
    #   time, not at request time. A malicious DNS server could return a safe
    #   IP during validation, then switch to an internal IP when OmniAuth
    #   actually fetches the metadata. Mitigating this requires DNS pinning
    #   or resolving the hostname and validating the resolved IP immediately
    #   before use, which is beyond the scope of this module.
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

        # Block private IP ranges
        begin
          ip = IPAddr.new(host)

          # Check for loopback, private, or link-local addresses
          return true if ip.loopback?
          return true if ip.private?
          return true if ip.link_local?
        rescue IPAddr::InvalidAddressError
          # Not an IP address, proceed with hostname
          false
        end

        false
      end
    end
  end
end
