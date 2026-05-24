# lib/onetime/models/custom_domain/signup_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::SignupConfig - Per-domain signup email validation strategy
#
# This model stores signup validation configuration bound to a specific CustomDomain.
# Enables per-tenant control over email validation during account creation.
#
# Use Cases:
#   - Open signup: secrets.acme.com allows any email (passthrough)
#   - Corporate restriction: secrets.corp.com restricts to @corp.com emails
#   - Strict validation: secrets.secure.com requires MX/SMTP verification
#
# Strategy Types:
#   - passthrough:      Format check only (BASIC_FORMAT regex)
#   - domain_allowlist: Email domain must be in allowed list
#   - mx:               Truemail MX lookup validation
#   - smtp:             Truemail SMTP validation (strictest)
#
# See: apps/api/account/logic/account/create_account.rb (signup flow)
#      apps/web/auth/config/hooks/omniauth.rb (SSO signup flow)
#
module Onetime
  class CustomDomain < Familia::Horreum
    class SignupConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-signup-config'

      # Supported validation strategy types
      STRATEGY_TYPES = %w[passthrough domain_allowlist mx smtp].freeze

      # Strategy metadata for UI/documentation
      STRATEGY_METADATA = {
        'passthrough' => {
          description: 'Format check only - accepts any valid email format',
          requires_allowlist: false,
          network_validation: false,
        },
        'domain_allowlist' => {
          description: 'Email domain must be in the configured allowed list',
          requires_allowlist: true,
          network_validation: false,
        },
        'mx' => {
          description: 'Validates email domain has MX records (DNS lookup)',
          requires_allowlist: false,
          network_validation: true,
        },
        'smtp' => {
          description: 'Full SMTP validation - strictest, may be slow',
          requires_allowlist: false,
          network_validation: true,
        },
      }.freeze

      prefix :custom_domain__signup_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one signup config per domain.
      identifier_field :domain_id
      field :domain_id

      # Core configuration fields
      field :validation_strategy  # One of STRATEGY_TYPES
      field :enabled              # Boolean string ('true'/'false')

      # Domain allowlist (JSON array string) - used when strategy is 'domain_allowlist'
      field :allowed_signup_domains_json

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled             ||= 'false'
        self.validation_strategy ||= 'passthrough'
      end

      # Check if this config is enabled.
      #
      # @return [Boolean] true if per-domain validation is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Returns metadata for the current validation strategy.
      #
      # @return [Hash] Strategy metadata
      def strategy_metadata
        STRATEGY_METADATA.fetch(validation_strategy, {})
      end

      # Whether this strategy requires an allowlist to be configured.
      #
      # @return [Boolean]
      def requires_allowlist?
        strategy_metadata.fetch(:requires_allowlist, false)
      end

      # Whether this strategy performs network validation (slower).
      #
      # @return [Boolean]
      def network_validation?
        strategy_metadata.fetch(:network_validation, false)
      end

      # Enable this signup config.
      # @return [void]
      def enable!
        self.enabled = 'true'
        save
      end

      # Disable this signup config.
      # @return [void]
      def disable!
        self.enabled = 'false'
        save
      end

      # Get the list of allowed signup email domains.
      #
      # @return [Array<String>] Lowercase domain names
      def allowed_signup_domains
        return [] if allowed_signup_domains_json.to_s.empty?

        JSON.parse(allowed_signup_domains_json)
      rescue JSON::ParserError
        []
      end

      # Set the list of allowed signup email domains.
      #
      # Validates each domain using PublicSuffix to ensure it has a valid TLD.
      #
      # @param domains [Array<String>] Domain names to allow
      # @return [void]
      # @raise [Onetime::Problem] if any domain is invalid
      def allowed_signup_domains=(domains)
        normalized = Array(domains).map { it.to_s.strip.downcase }.uniq.reject(&:empty?)

        # Validate each domain using PublicSuffix
        normalized.each do |domain|
          Utils::DomainParser.cached_parse(domain)
        rescue PublicSuffix::Error => ex
          raise Onetime::Problem, "Invalid domain: #{domain} (#{ex.message})"
        end

        self.allowed_signup_domains_json = normalized.empty? ? nil : JSON.generate(normalized)
      end

      # Validate an email address against the allowed domains list.
      #
      # @param email [String] Email address to validate
      # @return [Boolean] true if email domain is allowed
      def valid_email_domain?(email)
        domains = allowed_signup_domains
        return true if domains.empty?

        email_domain = email.to_s.split('@').last&.downcase
        return false if email_domain.nil? || email_domain.empty?

        domains.include?(email_domain)
      end

      # Validate an email address using this config's strategy.
      #
      # @param email [String] Email address to validate
      # @return [Boolean] true if email passes validation
      def valid_signup_email?(email)
        case validation_strategy
        when 'passthrough'
          validate_passthrough(email)
        when 'domain_allowlist'
          validate_domain_allowlist(email)
        when 'mx'
          validate_with_truemail(email, :mx)
        when 'smtp'
          validate_with_truemail(email, :smtp)
        else
          # Unknown strategy - fail closed
          false
        end
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
        domain = custom_domain
        return nil unless domain

        Onetime::Organization.load(domain.org_id)
      end

      # Validate that all required fields are present.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?
        errors << 'validation_strategy is required' if validation_strategy.to_s.empty?
        errors << "validation_strategy must be one of: #{STRATEGY_TYPES.join(', ')}" unless STRATEGY_TYPES.include?(validation_strategy)

        # domain_allowlist strategy requires at least one domain
        if validation_strategy == 'domain_allowlist' && allowed_signup_domains.empty?
          errors << 'allowed_signup_domains is required for domain_allowlist strategy'
        end

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      class << self
        # Returns strategy metadata for all supported strategies.
        #
        # @return [Hash] Strategy type => metadata hash
        def strategy_metadata
          STRATEGY_METADATA
        end

        # Returns metadata for a specific strategy type.
        #
        # @param strategy_type [String] One of STRATEGY_TYPES
        # @return [Hash] Strategy metadata or empty hash
        def metadata_for(strategy_type)
          STRATEGY_METADATA.fetch(strategy_type.to_s, {})
        end

        # Find signup config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::SignupConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Check if a domain has signup config.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if signup config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new signup config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::SignupConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Signup config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          # Set fields
          config.validation_strategy = attrs[:validation_strategy] if attrs.key?(:validation_strategy)
          config.enabled             = attrs[:enabled].to_s if attrs.key?(:enabled)

          # Set allowed domains
          config.allowed_signup_domains = attrs[:allowed_signup_domains] if attrs.key?(:allowed_signup_domains)

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save

          config
        end

        # Delete signup config for a domain.
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

        # List all domain signup configs.
        #
        # @return [Array<CustomDomain::SignupConfig>] All configs (newest first)
        def all
          identifiers = instances.revrangeraw(0, -1)
          return [] if identifiers.empty?

          load_multi(identifiers).compact
        end

        # Count of domains with signup config.
        #
        # @return [Integer] Number of signup configs
        def count
          instances.size
        end
      end

      private

      # Format-only validation using BASIC_FORMAT regex.
      def validate_passthrough(email)
        Onetime::Utils::EmailFormat.valid_format?(email)
      end

      # Domain allowlist validation.
      def validate_domain_allowlist(email)
        # Must also pass format check
        return false unless Onetime::Utils::EmailFormat.valid_format?(email)

        valid_email_domain?(email)
      end

      # Truemail validation with per-call configuration.
      #
      # @param email [String] Email to validate
      # @param validation_type [Symbol] :mx or :smtp
      # @return [Boolean] true if email passes validation
      def validate_with_truemail(email, validation_type)
        # Must also pass format check first
        return false unless Onetime::Utils::EmailFormat.valid_format?(email)

        custom_config = build_truemail_config(validation_type: validation_type)
        result        = Truemail.validate(email, custom_configuration: custom_config)
        result.result.success
      rescue StandardError => ex
        OT.le "[SignupConfig] Truemail validation error: #{ex.message}"
        # On error, fall back to format-only validation
        Onetime::Utils::EmailFormat.valid_format?(email)
      end

      # Build a per-call Truemail configuration.
      #
      # @param validation_type [Symbol] :mx or :smtp
      # @return [Truemail::Configuration]
      def build_truemail_config(validation_type:)
        Truemail::Configuration.new do |config|
          # Copy essential settings from global config
          global_config = Truemail.configuration

          config.verifier_email     = global_config.verifier_email
          config.verifier_domain    = global_config.verifier_domain
          config.connection_timeout = global_config.connection_timeout
          config.response_timeout   = global_config.response_timeout

          # Set the requested validation type
          config.default_validation_type = validation_type
        end
      end
    end
  end
end
