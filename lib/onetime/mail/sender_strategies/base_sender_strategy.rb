# lib/onetime/mail/sender_strategies/base_sender_strategy.rb
#
# frozen_string_literal: true

require 'resolv'
require 'digest'

module Onetime
  module Mail
    module SenderStrategies
      # BaseSenderStrategy - Interface for sender domain provisioning strategies.
      #
      # Sender strategies handle DNS record provisioning for email sender
      # authentication (DKIM, SPF, etc.) through mail provider APIs. This is
      # separate from the Delivery backends which handle actual email sending.
      #
      # Each strategy implements provider-specific logic for:
      #   - Provisioning sender identities and retrieving DNS records
      #   - Checking verification status
      #   - Cleaning up/removing sender identities
      #
      # Strategy Capabilities:
      #
      #   | Strategy   | provision | verify | cleanup |
      #   |------------|-----------|--------|---------|
      #   | SES        | yes       | yes    | yes     |
      #   | SendGrid   | yes       | yes    | yes     |
      #   | Lettermint | yes       | yes    | yes     |
      #   | SMTP       | no-op     | no-op  | no-op   |
      #
      # DNS Record Types by Provider:
      #
      #   SES:       3 CNAME records for DKIM tokens
      #   SendGrid:  Multiple CNAME/TXT records (branded links, DKIM, SPF)
      #   Lettermint: CNAME/TXT records for DKIM selectors and SPF
      #
      class BaseSenderStrategy
        attr_reader :config

        # Initialize with provider configuration.
        #
        # @param config [Hash] Provider-specific configuration (credentials, region, etc.)
        #
        def initialize(config = {})
          @config = config
          validate_config!
        end

        # Provisions sender DNS records through the provider API.
        #
        # This creates or retrieves the sender identity/domain in the provider
        # and returns the DNS records that must be configured for authentication.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials (api_key, region, etc.)
        # @return [Hash] Provider-specific DNS provisioning data:
        #   - :success [Boolean] Whether provisioning succeeded
        #   - :message [String] Human-readable result
        #   - :dns_records [Array<Hash>] Normalized DNS records, each with:
        #     - :type [String] Record type ('CNAME', 'TXT', etc.)
        #     - :name [String] DNS hostname
        #     - :value [String] DNS record value
        #   - :provider_data [Hash] Raw provider metadata (tokens, regions, status)
        #   - :identity_id [String, nil] Provider's identity identifier
        #   - :error [String, nil] Error message if failed
        #
        def provision_dns_records(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #provision_dns_records"
        end

        # Checks the provider-level verification status of a sender identity.
        #
        # Queries the provider API (SES, SendGrid, Lettermint) to determine
        # whether the provider considers the sender domain verified. This is
        # distinct from check_dns_records which verifies DNS propagation
        # independently of the provider.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials
        # @return [Hash] Verification status:
        #   - :verified [Boolean] Whether the sender is verified
        #   - :status [String] Provider-specific status code
        #   - :message [String] Human-readable status
        #   - :details [Hash, nil] Additional verification details
        #
        def check_provider_verification_status(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #check_provider_verification_status"
        end

        # Checks DNS record propagation for provisioned sender records.
        #
        # Reads the provisioned DNS records from mailer_config.dns_records
        # and performs live DNS lookups to determine whether each record
        # exists and whether its value matches what was provisioned.
        #
        # This is a fact-finding operation — it reports what DNS returns
        # without making pass/fail judgements. Consumers decide whether
        # record existence alone is sufficient or if value matching is
        # required.
        #
        # Implemented at the base class level because it uses provisioned
        # records (provider-agnostic). Override in subclasses only if the
        # provider's DNS record format requires special lookup handling.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Unused (DNS lookups need no credentials)
        # @return [Hash] DNS check results:
        #   - :records [Array<Hash>] Per-record results, each with:
        #     - :type [String] Record type (TXT, CNAME, MX)
        #     - :name [String] DNS hostname
        #     - :value [String] Expected value from provisioning
        #     - :dns_exists [Boolean] Whether any DNS records exist for this name+type
        #     - :value_matches [Boolean] Whether provisioned value matches DNS
        #     - :error [String, nil] Error message on lookup failure
        #     - :expected_digest [String] SHA256 hex digest of normalized expected value
        #     - :actual_digest [String, nil] SHA256 hex digest of best-matching actual value
        #   - :checked_at [Time] When the check was performed
        #
        def check_dns_records(mailer_config, credentials: {}) # rubocop:disable Lint/UnusedMethodArgument
          provisioned = mailer_config.dns_records&.value
          return { records: [], checked_at: Time.now } if provisioned.nil? || provisioned.empty?

          resolver          = Resolv::DNS.new
          resolver.timeouts = 5

          results = provisioned.map do |record|
            check_single_dns_record(record, resolver)
          end

          { records: results, checked_at: Time.now }
        ensure
          resolver&.close
        end

        # Removes the sender identity from the provider.
        #
        # @param mailer_config [CustomDomain::MailerConfig] The mailer configuration
        # @param credentials [Hash] Provider credentials
        # @return [Hash] Deletion result:
        #   - :deleted [Boolean] Whether deletion was performed
        #   - :message [String] Human-readable result
        #
        def delete_sender_identity(mailer_config, credentials:)
          raise NotImplementedError, "#{self.class} must implement #delete_sender_identity"
        end

        # Returns the strategy name for logging and debugging.
        #
        # @return [String] Strategy identifier (e.g., 'ses', 'sendgrid')
        #
        def strategy_name
          self.class.name.split('::').last.sub('SenderStrategy', '').downcase
        end

        # Checks if this strategy supports DNS provisioning.
        #
        # SMTP strategy returns false since it doesn't have API-based provisioning.
        #
        # @return [Boolean]
        #
        def supports_provisioning?
          true
        end

        protected

        # Override in subclasses for provider-specific validation.
        #
        def validate_config!
          # Base implementation does nothing
        end

        # Log info message with OT logger fallback.
        #
        # @param message [String] Message to log
        #
        def log_info(message)
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        # Log error message with OT logger fallback.
        #
        # @param message [String] Message to log
        #
        def log_error(message)
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        # Extract the domain from an email address.
        #
        # Uses Truemail regex validation to reject malformed addresses
        # before extracting the domain portion.
        #
        # @param email [String] Email address
        # @return [String, nil] Domain portion, or nil if invalid
        #
        def extract_domain(email)
          return nil if email.to_s.empty?

          result = Truemail.validate(email, with: :regex)
          return nil unless result.result.valid?

          email.split('@', 2).last
        end

        private

        # Check a single DNS record against live DNS.
        #
        # @param record [Hash] Provisioned record with string keys: 'type', 'name', 'value'
        # @param resolver [Resolv::DNS] Shared resolver instance
        # @return [Hash] Check result with :dns_exists, :value_matches, :error, digests
        #
        def check_single_dns_record(record, resolver)
          rec_type  = record['type'].to_s.upcase
          rec_name  = record['name'].to_s
          rec_value = record['value'].to_s

          expected_normalized = normalize_dns_value(rec_value)
          expected_digest     = Digest::SHA256.hexdigest(expected_normalized)

          actual_values, error = lookup_dns_record(rec_type, rec_name, resolver)

          dns_exists    = !actual_values.empty?
          value_matches = false
          actual_digest = nil

          if dns_exists
            actual_values.each do |actual|
              normalized_actual = normalize_dns_value(actual)
              digest            = Digest::SHA256.hexdigest(normalized_actual)
              if normalized_actual == expected_normalized || digest == expected_digest
                value_matches = true
                actual_digest = digest
                break
              end
              # Track the first actual digest for debugging even if no match
              actual_digest   ||= digest
            end
          end

          {
            type: rec_type,
            name: rec_name,
            value: rec_value,
            dns_exists: dns_exists,
            value_matches: value_matches,
            error: error,
            expected_digest: expected_digest,
            actual_digest: actual_digest,
          }
        end

        # Perform a DNS lookup by record type.
        #
        # @param type [String] Record type: TXT, CNAME, or MX
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] DNS resolver instance
        # @return [Array] Tuple of [Array<String>, String|nil] — [values, error]
        #
        def lookup_dns_record(type, hostname, resolver)
          case type
          when 'TXT'
            resources = resolver.getresources(hostname, Resolv::DNS::Resource::IN::TXT)
            [resources.map { |r| r.strings.join }, nil]
          when 'CNAME'
            resources = resolver.getresources(hostname, Resolv::DNS::Resource::IN::CNAME)
            [resources.map { |r| r.name.to_s }, nil]
          when 'MX'
            resources = resolver.getresources(hostname, Resolv::DNS::Resource::IN::MX)
            [resources.map { |r| r.exchange.to_s }, nil]
          else
            [[], nil]
          end
        rescue Resolv::ResolvError
          # NXDOMAIN or similar authoritative "not found" — definitive answer, not an error
          [[], nil]
        rescue Resolv::ResolvTimeout
          [[], 'timeout']
        rescue StandardError => ex
          [[], ex.message]
        end

        # Normalize a DNS value for comparison.
        #
        # Downcases and strips trailing dots to handle variations in DNS
        # responses (e.g., "bounces.lmta.net." vs "bounces.lmta.net").
        #
        # @param value [String] Raw DNS value
        # @return [String] Normalized value
        #
        def normalize_dns_value(value)
          value.to_s.downcase.chomp('.')
        end
      end
    end
  end
end
