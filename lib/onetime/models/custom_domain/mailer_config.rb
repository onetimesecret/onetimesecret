# lib/onetime/models/custom_domain/mailer_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::MailerConfig - Per-domain mail sender configuration
#
# This model stores mail sender credentials bound to a specific CustomDomain.
# This enables per-domain email configuration where different domains owned
# by the same organization can use different mail providers and sender
# identities.
#
# Use Cases:
#   - Brand consistency: secrets.acme.eu sends from noreply@acme.eu, secrets.acme.com from noreply@acme.com
#   - Provider isolation: one domain uses SES, another uses SendGrid
#   - Compliance: regional domains use region-specific mail infrastructure
#
# Credential Binding:
#   The api_key is encrypted with AAD (Additional Authenticated Data) bound
#   to domain_id, preventing credential swapping attacks between domains.
#
# Verification Semantics:
#   - Changing from_address resets verified_at (DNS verification no longer applies)
#   - Changing api_key, from_name, or reply_to does NOT reset verified_at
#
# DNS Data Storage (two-field design):
#   - provider_dns_data (jsonkey): Raw provider response hash, shape varies by provider.
#     Preserved for re-normalization and provider-specific operations.
#   - dns_records (jsonkey): Normalized Array of record hashes for UI display,
#     each with :type, :name, :value keys. Populated during provisioning.
#
module Onetime
  class CustomDomain < Familia::Horreum
    class MailerConfig < Familia::Horreum
      include Familia::Features::Autoloader

      # Supported mail provider types.
      # See lib/onetime/mail/mailer.rb for provider implementations.
      PROVIDER_TYPES = %w[smtp ses sendgrid lettermint].freeze

      prefix :custom_domain__mailer_config

      feature :encrypted_fields

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one mailer config per domain.
      identifier_field :domain_id
      field :domain_id

      # Provider selection
      field :provider         # One of PROVIDER_TYPES

      # Sender identity fields
      field :from_name        # Display name for sender
      field :from_address     # Sender email address
      field :reply_to         # Reply-to address

      # DNS verification state
      field :verification_status  # pending, verified, failed
      field :verified_at          # Timestamp, cleared when from_address changes

      # Sending mode: 'platform' (OTS manages DNS via provider API) or
      # future modes like 'byodns' (customer manages DNS manually).
      # Currently only 'platform' is supported.
      field :sending_mode

      # Provider-specific DNS/identity data returned from provider APIs.
      # Shape varies by provider:
      #   SES: { dkim_tokens: [...], region: "us-east-1", identity_arn: "..." }
      #   SendGrid: { subdomain: "em1234", dns_records: [...] }
      jsonkey :provider_dns_data

      # Normalized DNS records for UI display.
      # Uniform array format: [{ type: 'CNAME', name: '...', value: '...' }, ...]
      # Populated during provisioning from provider-specific dns_records.
      jsonkey :dns_records

      # Encrypted credential storage with domain-bound AAD
      encrypted_field :api_key, aad_fields: [:domain_id]

      # Distributed lock for concurrent provisioning protection
      lock :provisioning

      # General state
      field :enabled          # Boolean string ('true'/'false')

      # Verification tracking fields (for caching and metrics)
      field :last_check_at      # Unix timestamp of last verification attempt
      field :check_duration_ms  # Duration of last check in milliseconds
      field :check_count        # Total number of verification attempts
      field :last_error         # Last error message if verification failed

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled             ||= 'false'
        self.verification_status ||= 'pending'
        self.sending_mode        ||= 'platform'
      end

      # Check if this mailer config is enabled.
      #
      # @return [Boolean] true if mailer config is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Check if the sender address has been verified via DNS.
      #
      # @return [Boolean] true if verification_status is 'verified'
      def verified?
        verification_status == 'verified'
      end

      # Update the from_address, resetting verification state.
      #
      # Changing the sender address invalidates any prior DNS verification
      # (DKIM/SPF records are bound to the sender domain), so verified_at
      # is cleared and verification_status reverts to 'pending'.
      #
      # @param new_address [String] The new sender email address
      # @return [void]
      def update_from_address(new_address)
        self.from_address        = new_address
        self.verified_at         = nil
        self.verification_status = 'pending'
        self.updated             = Familia.now.to_i
        save
      end

      # Rotate the API key without affecting verification state.
      #
      # Credential rotation is independent of DNS verification -- the
      # DKIM/SPF records don't change when the API key changes.
      #
      # @param new_api_key [String] The new provider API key
      # @return [void]
      def rotate_credentials(new_api_key)
        self.api_key = new_api_key
        self.updated = Familia.now.to_i
        save
      end

      # Load the associated CustomDomain record.
      #
      # @return [CustomDomain, nil] The domain or nil if not found
      def custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Load the owning Organization via the CustomDomain.
      #
      # @return [Organization, nil] The organization or nil if not found
      def organization
        custom_domain&.primary_organization
      end

      # Validate that all required fields are present.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?
        # Provider is optional - when empty, resolved from installation config
        if !provider.to_s.empty? && !PROVIDER_TYPES.include?(provider)
          errors << "provider must be one of: #{PROVIDER_TYPES.join(', ')}"
        end
        errors << 'from_address is required' if from_address.to_s.empty?

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      # Record a verification check attempt with timing and optional error.
      #
      # Updates tracking fields for caching decisions and operational metrics.
      # Called by ValidateSenderDomain after each verification attempt.
      #
      # Uses save_fields for field-specific persistence to avoid race
      # conditions where a full save could overwrite concurrent updates
      # to other fields.
      #
      # @param duration_ms [Integer] How long the check took in milliseconds
      # @param error [String, nil] Error message if the check failed
      # @return [void]
      def record_check_attempt(duration_ms, error = nil)
        self.last_check_at     = Familia.now.to_i
        self.check_duration_ms = duration_ms.to_i
        self.check_count       = (check_count.to_i + 1).to_s
        self.last_error        = error
        self.updated           = Familia.now.to_i
        save_fields(:last_check_at, :check_duration_ms, :check_count, :last_error, :updated)
      end

      # Check if a recent verification check was performed.
      #
      # Used for caching decisions to avoid excessive DNS lookups.
      #
      # @param max_age_seconds [Integer] Maximum age for a check to be considered recent
      # @return [Boolean] true if a check was performed within max_age_seconds
      def check_recent?(max_age_seconds = 300)
        return false if last_check_at.to_s.empty?

        (Familia.now.to_i - last_check_at.to_i) < max_age_seconds
      end

      # Check if the sender domain has been provisioned.
      #
      # A domain is considered provisioned when dns_records contains
      # normalized records from the provider API (SES, SendGrid, etc.).
      #
      # @return [Boolean] true if dns_records is populated
      def provisioned?
        data = dns_records&.value
        data.is_a?(Array) && !data.empty?
      end

      # Build DNS records required for email authentication.
      #
      # Returns the DNS records that must be configured at the domain registrar.
      # After provisioning, this returns the actual records from the provider.
      # Before provisioning, returns an empty array.
      #
      # Each record includes:
      #   - type: DNS record type (CNAME, TXT, etc.)
      #   - name: DNS hostname
      #   - value: DNS record value
      #   - status: Verification status ('pending', 'verified', 'failed')
      #
      # @return [Array<Hash>] DNS records for user to configure
      def required_dns_records
        return [] unless provisioned?

        data           = dns_records.value
        current_status = verification_status || 'pending'

        data.map do |record|
          # Ensure consistent shape: type, name, value, status
          {
            type: record['type'] || record[:type],
            name: record['name'] || record[:name],
            value: record['value'] || record[:value],
            status: current_status,
          }.compact
        end
      end

      class << self
        # Find mailer config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::MailerConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Load sender config with graceful fallback.
        #
        # Wraps find_by_domain_id with broader error handling. Returns nil
        # on missing config or any error — callers treat nil as "use
        # system default sender config".
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::MailerConfig, nil] The config or nil
        def load_for_domain(domain_id)
          config = find_by_domain_id(domain_id)
          unless config
            OT.info "[MailerConfig] No sender config for domain_id=#{domain_id}, using global mailer"
            return nil
          end
          config
        rescue StandardError => ex
          OT.le "[MailerConfig] Failed to load sender config for domain_id=#{domain_id}: #{ex.message}"
          nil
        end

        # Check if a domain has mailer configuration.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if mailer config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new mailer config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::MailerConfig] The created config
        # @raise [Onetime::Problem] if config already exists or validation fails
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Mailer config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          # Set provider and sender identity fields
          config.provider     = attrs[:provider] if attrs.key?(:provider)
          config.from_name    = attrs[:from_name] if attrs.key?(:from_name)
          config.from_address = attrs[:from_address] if attrs.key?(:from_address)
          config.reply_to     = attrs[:reply_to] if attrs.key?(:reply_to)
          config.enabled      = attrs[:enabled].to_s if attrs.key?(:enabled)

          # Set verification and mode fields
          config.verification_status = attrs[:verification_status] if attrs.key?(:verification_status)
          config.sending_mode        = attrs[:sending_mode] if attrs.key?(:sending_mode)

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          unless config.valid?
            raise Onetime::Problem, config.validation_errors.join('; ')
          end

          config.save

          # Set encrypted fields AFTER save so the AAD context includes
          # aad_fields values (Familia's build_aad uses record.exists? to
          # decide whether to include aad_fields in the AAD hash). Setting
          # api_key before save would encrypt with pre-save AAD, but reveal
          # after save computes post-save AAD -- causing decryption failure.
          if attrs.key?(:api_key)
            config.api_key = attrs[:api_key]
            config.commit_fields
          end

          config
        end

        # Delete mailer config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          config.destroy!

          true
        end

        # List all domain mailer configs.
        #
        # @return [Array<CustomDomain::MailerConfig>] All configs (newest first)
        def all
          instances.revrangeraw(0, -1).filter_map do |identifier|
            load(identifier)
          rescue Onetime::RecordNotFound
            nil
          end
        end

        # Count of domains with mailer configuration.
        #
        # @return [Integer] Number of mailer configs
        def count
          instances.size
        end
      end
    end
  end
end
