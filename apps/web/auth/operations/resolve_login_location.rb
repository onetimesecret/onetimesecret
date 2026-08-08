# apps/web/auth/operations/resolve_login_location.rb
#
# frozen_string_literal: true

#
# Resolves a privacy-safe "location" string for the new-sign-in / MFA
# security-alert emails (issue #3989), shared by hooks/login.rb and
# hooks/mfa.rb so both alerts use one policy.
#
# PURE FUNCTION: accepts only primitive data (no request/env objects) — the
# same convention as Auth::Operations::DetectMfaRequirement.
#
# NEVER returns a raw IP address. In priority order:
#   1. The resolved ISO 3166-1 alpha-2 country code, when Otto's
#      IPPrivacyMiddleware actually resolved one (env['otto.privacy.geo_country'],
#      excluding Otto's '**' unknown sentinel).
#   2. Otherwise the already-MASKED client IP (env['otto.client_ip'], set by
#      IPPrivacyMiddleware) — never request.ip / REMOTE_ADDR, which are raw.
#   3. 'Unknown location' when neither is available.
#
module Auth
  module Operations
    class ResolveLoginLocation
      # Otto::Privacy::GeoResolver::UNKNOWN — "no country resolved".
      UNKNOWN_COUNTRY = '**'
      FALLBACK        = 'Unknown location'

      # @param geo_country [String, nil] request.env['otto.privacy.geo_country']
      # @param masked_ip [String, nil] request.env['otto.client_ip'] (masked)
      # @return [String] a country code, a masked IP, or FALLBACK — never a raw IP
      def self.call(geo_country:, masked_ip:)
        country = normalize_country(geo_country)
        return country if country
        return masked_ip if masked_ip.is_a?(String) && !masked_ip.strip.empty?

        FALLBACK
      end

      # Strip/upcase to the canonical alpha-2 form, mirroring
      # Onetime::Security::RequestContext#normalize_country so a deployment whose
      # custom geo header emits a lowercase or whitespace-padded code still
      # prefers the country over the masked IP. Returns nil for the '**' unknown
      # sentinel, a blank value, or anything not a well-formed alpha-2 code.
      def self.normalize_country(code)
        return nil unless code.is_a?(String)

        normalized = code.strip.upcase
        return nil if normalized == UNKNOWN_COUNTRY
        return nil unless normalized.match?(/\A[A-Z]{2}\z/)

        normalized
      end
      private_class_method :normalize_country
    end
  end
end
