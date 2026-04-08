# lib/onetime/domain_validation/sender_strategies/lettermint_validation.rb
#
# frozen_string_literal: true

require_relative 'base_strategy'

module Onetime
  module DomainValidation
    module SenderStrategies
      # LettermintValidation - Lettermint sender domain validation strategy.
      #
      # Reads provisioned DNS records from mailer_config.dns_records rather
      # than generating them from hardcoded selectors. The Lettermint API
      # provisions the actual records at domain creation time.
      #
      # Known Lettermint failure states:
      #   - API may return empty dns_records array if domain creation is
      #     incomplete or still propagating internally.
      #   - Individual records may have status: 'pending' vs status: 'active'
      #     at the API level, though this is not reflected in the stored
      #     dns_records array (only name/type/value are persisted).
      #
      # Reference: Lettermint documentation (provider-specific)
      #
      class LettermintValidation < BaseStrategy
        # Returns the DNS records required for Lettermint domain verification.
        #
        # Reads provisioned records from mailer_config.dns_records.value
        # (array of string-keyed hashes from the Lettermint API) and maps
        # them to the validation format with symbol keys.
        #
        # Returns an empty array if no provisioned records exist — does
        # NOT fall back to hardcoded selectors.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash: {type:, host:, value:, purpose:}
        #
        def required_dns_records(mailer_config)
          provisioned = mailer_config.dns_records&.value

          if provisioned.nil? || provisioned.empty?
            logger.error "[lettermint-validation] No provisioned DNS records for #{mailer_config.domain_id}; cannot validate"
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

        # Verifies Lettermint DNS records via live DNS lookup.
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
          'lettermint'
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
          elsif name.include?('_dmarc')
            'DMARC'
          elsif name.include?('bounce') || (type == 'CNAME' && name.start_with?('lm-bounce'))
            'SPF/Return-Path'
          elsif type == 'TXT' && record['value'].to_s.start_with?('v=spf1')
            'SPF'
          elsif type == 'MX'
            'Inbound mail'
          else
            type
          end
        end
      end
    end
  end
end
