# lib/onetime/domain_validation/sender_strategies/lettermint_validation.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    module SenderStrategies
      # LettermintValidation - Lettermint sender domain validation strategy.
      #
      # Lettermint domain verification requires:
      #   - 2 CNAME records for DKIM (lm1, lm2 selectors)
      #   - 1 TXT record for SPF alignment
      #
      # Reference: Lettermint documentation (provider-specific)
      #
      class LettermintValidation < BaseStrategy
        DKIM_SELECTORS = %w[lm1 lm2].freeze
        SPF_INCLUDE    = 'lettermint.com'

        # Returns the DNS records required for Lettermint domain verification.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def required_dns_records(mailer_config)
          domain = resolve_domain(mailer_config)

          records = []

          # DKIM CNAME records (lm1, lm2 selectors)
          DKIM_SELECTORS.each_with_index do |selector, i|
            records << {
              type: 'CNAME',
              host: "#{selector}._domainkey.#{domain}",
              value: "#{selector}.dkim.#{SPF_INCLUDE}",
              purpose: "DKIM signature #{i + 1} of #{DKIM_SELECTORS.size}",
            }
          end

          # SPF TXT record
          records << {
            type: 'TXT',
            host: domain,
            value: "v=spf1 include:#{SPF_INCLUDE} ~all",
            purpose: 'SPF authentication',
          }

          records
        end

        # Verifies Lettermint DNS records via live DNS lookup.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def verify_dns_records(mailer_config)
          verify_all_records(mailer_config)
        end

        # @return [String]
        def strategy_name
          'lettermint'
        end
      end
    end
  end
end
