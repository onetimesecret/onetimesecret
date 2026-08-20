# lib/onetime/domain_validation/sender_strategies/smtp2go_validation.rb
#
# frozen_string_literal: true

require_relative 'base_strategy'

module Onetime
  module DomainValidation
    module SenderStrategies
      # Smtp2goValidation - SMTP2GO sender domain validation strategy.
      #
      # Reads provisioned DNS records from mailer_config.dns_records rather
      # than generating them from hardcoded selectors. The SMTP2GO API
      # provisions the actual records (DKIM selector included) at domain
      # add time.
      #
      # SMTP2GO uses three CNAME records per domain:
      #   - <selector>._domainkey.<domain> -> dkim.smtp2go.net    (DKIM)
      #   - <rpath_subdomain>.<domain>     -> return.smtp2go.net  (SPF/Return-Path)
      #   - <tracking_subdomain>.<domain>  -> track.smtp2go.net   (Tracking)
      #
      # Known SMTP2GO failure states:
      #   - Records carry per-record verified booleans at the API level
      #     (dkim_verified/rpath_verified/cname_verified), surfaced as a
      #     'status' key in the stored dns_records array.
      #   - SMTP2GO re-polls DNS every ~7 minutes; the provider-side status
      #     can lag recent DNS changes until /domain/verify is triggered.
      #
      # Reference: https://developers.smtp2go.com (provider-specific)
      #
      class Smtp2goValidation < BaseStrategy
        # DNS records come from BaseStrategy#required_dns_records, which
        # reads provisioned mailer_config.dns_records and skips the
        # advisory tracking CNAME ('optional' => true) so it never gates
        # verification.

        # Verifies SMTP2GO DNS records via live DNS lookup.
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
          'smtp2go'
        end

        private

        # Infers a human-readable purpose from the record's name and value.
        #
        # The smtp2go.net target matching is deliberately tolerant
        # ('return.smtp2go' / 'track.smtp2go' substrings) so a custom
        # return-path or tracking subdomain still classifies correctly.
        #
        # @param record [Hash] String-keyed hash from provisioned dns_records
        # @return [String]
        #
        def classify_record_purpose(record)
          name  = record['name'].to_s.downcase
          value = record['value'].to_s.downcase
          type  = record['type'].to_s.upcase

          if name.include?('_domainkey')
            'DKIM'
          elsif name.include?('_dmarc')
            'DMARC'
          elsif value.include?('return.smtp2go') || name.start_with?('bounce.')
            'SPF/Return-Path'
          elsif value.include?('track.smtp2go')
            'Tracking'
          elsif type == 'TXT' && record['value'].to_s.start_with?('v=spf1')
            'SPF'
          else
            type
          end
        end
      end
    end
  end
end
