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
        # Legacy constants preserved for backward compatibility.
        # New code should rely on ProviderConfig defaults.
        DKIM_SELECTORS = %w[lm1 lm2].freeze
        SPF_INCLUDE    = 'lettermint.com'

        def self.accepted_options
          [:dkim_selectors, :spf_include].freeze
        end

        # @param dkim_selectors [Array<String>] DKIM selector names (default: ['lm1', 'lm2'])
        # @param spf_include [String] SPF include domain (default: 'lettermint.com')
        def initialize(dkim_selectors: DKIM_SELECTORS, spf_include: SPF_INCLUDE)
          @dkim_selectors = dkim_selectors
          @spf_include    = spf_include
        end

        # Returns the DNS records required for Lettermint domain verification.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def required_dns_records(mailer_config)
          domain = resolve_domain(mailer_config)

          records = []

          # DKIM CNAME records (configurable selectors, default lm1, lm2)
          @dkim_selectors.each_with_index do |selector, i|
            records << {
              type: 'CNAME',
              host: "#{selector}._domainkey.#{domain}",
              value: "#{selector}.dkim.#{@spf_include}",
              purpose: "DKIM signature #{i + 1} of #{@dkim_selectors.size}",
            }
          end

          # SPF TXT record
          records << {
            type: 'TXT',
            host: domain,
            value: "v=spf1 include:#{@spf_include} ~all",
            purpose: 'SPF authentication',
          }

          records
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
      end
    end
  end
end
