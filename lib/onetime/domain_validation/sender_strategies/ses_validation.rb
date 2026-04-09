# lib/onetime/domain_validation/sender_strategies/ses_validation.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    module SenderStrategies
      # SesValidation - AWS SES sender domain validation strategy.
      #
      # Reads provisioned DNS records from mailer_config.dns_records rather
      # than generating them from hardcoded placeholder selectors. SES assigns
      # unique DKIM tokens per domain at verification time, so the real
      # records must come from the SES API response stored during provisioning.
      #
      # Reference: https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html
      #
      class SesValidation < BaseStrategy
        # Returns the DNS records required for SES domain verification.
        #
        # Reads provisioned records from mailer_config.dns_records.value
        # (array of string-keyed hashes from the SES API) and maps them
        # to the validation format with symbol keys.
        #
        # Returns an empty array if no provisioned records exist — does
        # NOT fall back to hardcoded placeholder selectors.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash: {type:, host:, value:, purpose:}
        #
        def required_dns_records(mailer_config)
          provisioned = mailer_config.dns_records&.value

          if provisioned.nil? || provisioned.empty?
            logger.error "[ses-validation] No provisioned DNS records for #{mailer_config.domain_id}; cannot validate"
            return []
          end

          provisioned.map do |record|
            {
              type: record['type'].to_s.upcase,
              host: record['name'].to_s,
              value: record['value'].to_s,
              purpose: classify_record_purpose(record),
            }
          end
        end

        # Verifies SES DNS records via live DNS lookup.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array<Hash>]
        #
        def verify_dns_records(mailer_config, bypass_cache: false)
          verify_all_records(mailer_config, bypass_cache: bypass_cache)
        end

        # @return [String]
        def strategy_name
          'ses'
        end

        private

        # Infers a human-readable purpose from the record's name and type.
        #
        # @param record [Hash] String-keyed hash from provisioned dns_records
        # @return [String]
        #
        def classify_record_purpose(record)
          name = record['name'].to_s.downcase
          type = record['type'].to_s.upcase

          if name.include?('_domainkey')
            'DKIM'
          elsif type == 'TXT' && record['value'].to_s.start_with?('v=spf1')
            'SPF'
          elsif type == 'MX'
            'Inbound mail (bounce handling)'
          elsif name.include?('_dmarc')
            'DMARC'
          else
            type
          end
        end
      end
    end
  end
end
