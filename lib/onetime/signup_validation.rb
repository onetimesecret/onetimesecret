# lib/onetime/signup_validation.rb
#
# frozen_string_literal: true

#
# Onetime::SignupValidation - Shared email validation for signup flows
#
# Provides per-domain validation strategy resolution with global config fallback.
# Used by both regular signup (CreateAccount) and SSO signup (before_omniauth_create_account).
#
# Resolution order:
#   1. If display_domain provided → load CustomDomain → load SignupConfig
#   2. If SignupConfig exists and is enabled → use its validation strategy
#   3. Otherwise → fall back to global allowed_signup_domains config
#
module Onetime
  module SignupValidation
    extend self

    # Mirrors the `accounts.valid_email` CHECK constraint
    # (apps/web/auth/migrations/001_initial.rb) so a claim rejected by the
    # database is also rejected here, before it ever reaches the INSERT.
    #
    # The CHECK is PostgreSQL-only (SQLite stores email as a plain String —
    # see that migration), so an SSO/OmniAuth email guard that only counts
    # '@' characters lets shapes through that 500 on the CHECK (internal
    # spaces, comma/semicolon in either part, a dotless domain) — the
    # Sequel::CheckConstraintViolation surfaces as the frozen-loading-screen
    # failure #3478 exists to prevent. Duplicating the pattern here — rather
    # than only relying on the database to raise — keeps the guard effective
    # on SQLite installs too, whose primary CI leg has no CHECK to catch a
    # regression of this kind.
    #
    # Anchored with \A/\z, not ^/$: Ruby's ^/$ match at line boundaries, so
    # "ok@example.com\nbad" would pass a ^/$ guard here and still be
    # rejected by PG (whose ^/$ are string anchors) — reintroducing the 500
    # this exists to prevent (#3971).
    VALID_EMAIL_PATTERN = /\A[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+\z/

    # @param email [String] Email address to validate
    # @return [Boolean] true if the email matches the accounts.valid_email shape
    def structurally_valid_email?(email)
      email.to_s.match?(VALID_EMAIL_PATTERN)
    end

    # Validate an email address for signup, with per-domain strategy support.
    #
    # @param email [String] Email address to validate
    # @param display_domain [String, nil] The custom domain context (from request)
    # @return [Boolean] true if email is allowed for signup
    def valid_signup_email?(email, display_domain: nil)
      # Try per-domain config first
      if display_domain
        custom_domain = CustomDomain.load_by_display_domain(display_domain)
        if custom_domain
          signup_config = CustomDomain::SignupConfig.find_by_domain_id(custom_domain.identifier)
          if signup_config&.enabled?
            return signup_config.valid_signup_email?(email)
          end
        end
      end

      # Fall back to global config
      global_allowed_domains?(email)
    end

    # Check email against global allowed_signup_domains config.
    #
    # @param email [String] Email address to validate
    # @return [Boolean] true if domain is allowed or no restrictions configured
    def global_allowed_domains?(email)
      allowed_domains = OT.conf.dig('site', 'authentication', 'allowed_signup_domains')

      # No restrictions configured - allow all domains
      return true if allowed_domains.nil? || allowed_domains.empty?

      # Extract domain from email
      email_parts = email.to_s.strip.downcase.split('@')

      # Reject malformed emails
      return false if email_parts.length != 2

      email_domain = email_parts.last

      # Reject empty domain
      return false if email_domain.nil? || email_domain.empty?

      # Case-insensitive domain matching
      normalized_domains = allowed_domains.compact.map(&:downcase)
      normalized_domains.include?(email_domain)
    end

    # Resolve the SignupConfig for a given display_domain.
    #
    # Useful when caller needs access to the config object itself,
    # not just the validation result.
    #
    # @param display_domain [String] The custom domain context
    # @return [CustomDomain::SignupConfig, nil] The enabled config or nil
    def resolve_signup_config(display_domain)
      return nil if display_domain.nil?

      custom_domain = CustomDomain.load_by_display_domain(display_domain)
      return nil unless custom_domain

      signup_config = CustomDomain::SignupConfig.find_by_domain_id(custom_domain.identifier)
      return nil unless signup_config&.enabled?

      signup_config
    end
  end
end
