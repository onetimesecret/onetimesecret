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
      field :dkim_record          # DKIM DNS record value
      field :spf_record           # SPF DNS record value
      field :verified_at          # Timestamp, cleared when from_address changes

      # Encrypted credential storage with domain-bound AAD
      encrypted_field :api_key, aad_fields: [:domain_id]

      # General state
      field :enabled          # Boolean string ('true'/'false')

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled             ||= 'false'
        self.verification_status ||= 'pending'
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
        if provider.to_s.empty?
          errors << 'provider is required'
        elsif !PROVIDER_TYPES.include?(provider)
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

          # Set DNS verification fields
          config.verification_status = attrs[:verification_status] if attrs.key?(:verification_status)
          config.dkim_record         = attrs[:dkim_record] if attrs.key?(:dkim_record)
          config.spf_record          = attrs[:spf_record] if attrs.key?(:spf_record)

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
