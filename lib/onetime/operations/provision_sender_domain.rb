# lib/onetime/operations/provision_sender_domain.rb
#
# frozen_string_literal: true

require_relative '../mail/sender_strategies'

module Onetime
  module Operations
    #
    # Provisions sender domain DNS records through the mail provider API.
    # Extracted from API logic for reuse in CLI tools, background jobs, and testing.
    #
    # This operation:
    #   1. Validates the mailer configuration has required fields
    #   2. Loads platform credentials for the provider
    #   3. Calls the provider-specific strategy to provision DNS records
    #   4. Stores the provider response in the mailer config
    #
    # Usage:
    #   result = ProvisionSenderDomain.new(mailer_config: config).call
    #   result.success       # => true/false
    #   result.dns_records   # => [{ type: 'CNAME', name: '...', value: '...' }, ...]
    #   result.error         # => 'Error message' or nil
    #
    # Options:
    #   - strategy: Custom provisioning strategy (default: from provider type)
    #   - persist: Whether to save provider_dns_data to config (default: true)
    #
    class ProvisionSenderDomain
      include Onetime::LoggerMethods

      # Immutable result for provisioning operation.
      #
      # @!attribute [r] success
      #   @return [Boolean] Whether provisioning succeeded
      # @!attribute [r] dns_records
      #   @return [Array<Hash>] Normalized DNS records for user display
      # @!attribute [r] provider_data
      #   @return [Hash, nil] Raw provider response for storage
      # @!attribute [r] error
      #   @return [String, nil] Error message if failed
      #
      Result = Data.define(:success, :dns_records, :provider_data, :error) do
        def success?
          success == true
        end

        def failed?
          !success?
        end

        def to_h
          {
            success: success,
            dns_records: dns_records,
            provider_data: provider_data,
            error: error,
          }
        end
      end

      # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration to provision
      # @param strategy [BaseSenderStrategy, nil] Custom strategy (default: based on provider)
      # @param persist [Boolean] Whether to save provider data to config (default: true)
      def initialize(mailer_config:, strategy: nil, persist: true)
        @mailer_config = mailer_config
        @strategy      = strategy
        @persist       = persist
      end

      # Executes the provisioning operation.
      #
      # Never raises - all errors are wrapped in the Result.
      #
      # @return [Result] Provisioning result with dns_records or error
      def call
        # Step 1: Validate mailer_config has required fields
        validation_error = validate_config
        return failure_result(validation_error) if validation_error

        provider = @mailer_config.provider

        # Step 2: Verify provider supports provisioning
        unless Onetime::Mail::SenderStrategies.supports_provisioning?(provider)
          return failure_result(
            "Provider '#{provider}' does not support automated DNS provisioning. " \
            'Configure DNS records manually.',
          )
        end

        # Step 3: Load platform credentials
        credentials = load_credentials(provider)
        return failure_result("Failed to load credentials for provider '#{provider}'") unless credentials

        # Step 4: Select strategy
        strategy = @strategy || Onetime::Mail::SenderStrategies.for_provider(provider)

        # Step 5: Call strategy.provision_dns_records
        #
        # NOTE: No client-side rate limiting is applied here. Currently
        # each call is a single user-triggered action so throttling is
        # unnecessary. If this operation is ever used in bulk (e.g.
        # batch provisioning for multiple domains), add a rate_limit
        # parameter with a sleep between calls — see VerifyDomain for
        # the pattern (0.5s default between bulk API calls). Provider
        # server-side limits to be aware of:
        #   - SES: 1 req/sec for CreateEmailIdentity
        #   - SendGrid: 600 req/min across all endpoints
        #   - Lettermint: undocumented, expect standard API limits
        #
        logger.info 'Provisioning sender domain',
          domain_id: @mailer_config.domain_id,
          provider: provider,
          from_address: @mailer_config.from_address

        provision_result = strategy.provision_dns_records(@mailer_config, credentials: credentials)

        # Step 6: Handle strategy result
        unless provision_result[:success]
          error_message = provision_result[:error] || provision_result[:message] || 'Provisioning failed'
          logger.warn 'Sender domain provisioning failed',
            domain_id: @mailer_config.domain_id,
            error: error_message
          return failure_result(error_message)
        end

        # Step 7: Extract and normalize DNS records
        dns_records   = normalize_dns_records(provision_result[:dns_records], provider)
        provider_data = provision_result[:provider_data]

        # Step 8: Store result in mailer_config and save if persist enabled
        if @persist
          persist_provider_data(provider_data, dns_records, provision_result[:identity_id])
        end

        logger.info 'Sender domain provisioned successfully',
          domain_id: @mailer_config.domain_id,
          provider: provider,
          record_count: dns_records.size

        Result.new(
          success: true,
          dns_records: dns_records,
          provider_data: provider_data,
          error: nil,
        )
      rescue ArgumentError => ex
        # Strategy selection or validation errors
        logger.error 'Provisioning argument error',
          domain_id: @mailer_config&.domain_id,
          error: ex.message
        failure_result(ex.message)
      rescue NotImplementedError => ex
        # Strategy method not yet implemented
        logger.warn 'Provisioning not implemented',
          domain_id: @mailer_config&.domain_id,
          error: ex.message
        failure_result("Provisioning not yet implemented: #{ex.message}")
      rescue StandardError => ex
        # Catch-all for unexpected errors
        logger.error 'Provisioning failed unexpectedly',
          domain_id: @mailer_config&.domain_id,
          error: ex.message,
          error_class: ex.class.name
        failure_result("Unexpected error: #{ex.message}")
      end

      private

      # Validate the mailer configuration has required fields for provisioning.
      #
      # @return [String, nil] Error message or nil if valid
      def validate_config
        return 'mailer_config is required' unless @mailer_config

        errors = []
        errors << 'provider is required' if @mailer_config.provider.to_s.empty?
        errors << 'from_address is required' if @mailer_config.from_address.to_s.empty?

        errors.empty? ? nil : errors.join('; ')
      end

      # Load and validate platform credentials for the provider.
      #
      # Mailer.provider_credentials always returns a Hash (even with nil
      # values when env vars are missing), so we validate that provider-
      # specific required keys are present and non-nil.
      #
      # @param provider [String] Provider name
      # @return [Hash, nil] Credentials hash or nil if not configured
      def load_credentials(provider)
        credentials = Onetime::Mail::Mailer.provider_credentials(provider)

        missing = missing_credential_keys(provider, credentials)
        unless missing.empty?
          logger.warn 'Provider credentials incomplete',
            provider: provider,
            missing_keys: missing
          return nil
        end

        credentials
      rescue StandardError => ex
        logger.error 'Failed to load provider credentials',
          provider: provider,
          error: ex.message
        nil
      end

      # Returns any required credential keys that are missing or nil.
      #
      # @param provider [String] Provider name
      # @param credentials [Hash] Credentials hash to validate
      # @return [Array<Symbol>] Missing key names (empty if all present)
      def missing_credential_keys(provider, credentials)
        required = case provider.to_s.downcase
                   when 'ses'
                     [:access_key_id, :secret_access_key, :region]
                   when 'sendgrid'
                     [:api_key]
                   when 'lettermint'
                     [:api_token]
                   when 'smtp'
                     [:host]
                   else
                     []
                   end

        required.select { |key| credentials[key].to_s.empty? }
      end

      # Normalize provider-specific DNS records to a consistent display format.
      #
      # Each provider returns DNS data in different shapes. This method
      # converts them to a common array of record hashes for UI display.
      #
      # @param dns_data [Array, Hash] Provider-specific DNS record data
      # @param provider [String] Provider name for format selection
      # @return [Array<Hash>] Normalized records: [{ type:, name:, value: }, ...]
      def normalize_dns_records(dns_data, provider)
        return [] if dns_data.nil?

        # Strategies return Arrays directly from :dns_records
        return dns_data if dns_data.is_a?(Array)

        case provider.to_s.downcase
        when 'ses'
          normalize_ses_records(dns_data)
        when 'sendgrid'
          normalize_sendgrid_records(dns_data)
        when 'lettermint'
          normalize_lettermint_records(dns_data)
        else
          # Generic passthrough for unknown providers
          dns_data[:records] || []
        end
      end

      # Normalize SES DKIM token format.
      #
      # SES returns: { dkim_tokens: ['token1', 'token2', 'token3'], region: 'us-east-1' }
      # We convert to CNAME records for user display.
      #
      # @param dns_data [Hash] SES DNS data
      # @return [Array<Hash>] CNAME records
      def normalize_ses_records(dns_data)
        tokens = dns_data[:dkim_tokens] || []
        domain = extract_domain_from_config

        tokens.map do |token|
          {
            type: 'CNAME',
            name: "#{token}._domainkey.#{domain}",
            value: "#{token}.dkim.amazonses.com",
          }
        end
      end

      # Normalize SendGrid domain authentication format.
      #
      # SendGrid returns various record types for branded links, DKIM, etc.
      #
      # @param dns_data [Hash] SendGrid DNS data
      # @return [Array<Hash>] DNS records
      def normalize_sendgrid_records(dns_data)
        records = []

        # SendGrid provider_data stores records under :dns (Hash of record hashes)
        if dns_data[:dns].is_a?(Hash)
          dns_data[:dns].each do |_key, record|
            next unless record.is_a?(Hash)

            records << {
              type: (record[:type] || record['type'] || 'CNAME').upcase,
              name: record[:host] || record['host'] || record[:name] || record['name'],
              value: record[:data] || record['data'] || record[:value] || record['value'],
            }
          end
        elsif dns_data[:cnames].is_a?(Hash)
          dns_data[:cnames].each do |_key, record|
            records << {
              type: record[:type] || 'CNAME',
              name: record[:host] || record[:name],
              value: record[:data] || record[:value],
            }
          end
        end

        records.compact
      end

      # Normalize Lettermint DNS record format.
      #
      # The Lettermint strategy already returns an Array of {type, name, value}
      # hashes from normalize_dns_records, so this is a passthrough. If for
      # some reason a Hash arrives (e.g., from stored provider_data), extract
      # the records array.
      #
      # @param dns_data [Array, Hash] Lettermint DNS data
      # @return [Array<Hash>] DNS records
      def normalize_lettermint_records(dns_data)
        return dns_data if dns_data.is_a?(Array)

        # Fallback for legacy Hash shapes
        dns_data[:all_records] || dns_data[:records] || dns_data[:selectors] || []
      end

      # Extract the domain from the mailer config's from_address.
      #
      # @return [String, nil] Domain portion of from_address
      def extract_domain_from_config
        from_address = @mailer_config&.from_address.to_s
        return nil if from_address.empty?

        parts = from_address.split('@')
        parts.length == 2 ? parts[1] : nil
      end

      # Persist provider data to the mailer config.
      #
      # Raises on failure so the caller's rescue block can build a proper
      # failure result.  Without this, a Redis failure would leave the
      # provider-side domain registered while the local config has no
      # record of it.
      #
      # @param provider_data [Hash] Raw provider-specific data to store
      # @param dns_records [Array<Hash>] Normalized DNS records for UI display
      # @param identity_id [String, nil] Provider's identity identifier
      # @raise [StandardError] if persistence fails
      def persist_provider_data(provider_data, dns_records, identity_id)
        @mailer_config.provider_dns_data = provider_data
        @mailer_config.dns_records       = dns_records
        @mailer_config.updated           = Familia.now.to_i
        @mailer_config.save

        logger.debug 'Persisted provider DNS data',
          domain_id: @mailer_config.domain_id,
          identity_id: identity_id,
          record_count: dns_records&.size
      end

      # Create a failure result with the given error message.
      #
      # @param error_message [String] Error description
      # @return [Result] Failed result
      def failure_result(error_message)
        Result.new(
          success: false,
          dns_records: [],
          provider_data: nil,
          error: error_message,
        )
      end

      # @return [SemanticLogger::Logger] Logger instance
      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
