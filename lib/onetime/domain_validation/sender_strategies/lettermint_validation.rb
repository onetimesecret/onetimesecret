# lib/onetime/domain_validation/sender_strategies/lettermint_validation.rb
#
# frozen_string_literal: true

require_relative 'base_strategy'

module Onetime
  module DomainValidation
    module SenderStrategies
      # LettermintValidation - Lettermint sender domain validation strategy.
      #
      # Lettermint domain verification requires:
      #   - 2 CNAME records for DKIM (lm1, lm2 selectors)
      #   - 1 CNAME record for SPF/Return-Path (lm-bounces subdomain)
      #
      # SPF is handled via CNAME, not a direct TXT record. Lettermint maintains
      # the SPF record at bounces.lmta.net, so users only need the CNAME.
      #
      # Reference: Lettermint documentation (provider-specific)
      #
      class LettermintValidation < BaseStrategy
        # Legacy constants preserved for backward compatibility.
        # New code should rely on ProviderConfig defaults.
        DKIM_SELECTORS   = %w[lm1 lm2].freeze
        SPF_CNAME_PREFIX = 'lm-bounces'
        SPF_CNAME_TARGET = 'bounces.lmta.net'

        def self.accepted_options
          [:dkim_selectors, :spf_cname_prefix, :spf_cname_target].freeze
        end

        # @param dkim_selectors [Array<String>] DKIM selector names (default: ['lm1', 'lm2'])
        # @param spf_cname_prefix [String] SPF CNAME subdomain prefix (default: 'lm-bounces')
        # @param spf_cname_target [String] SPF CNAME target domain (default: 'bounces.lmta.net')
        def initialize(dkim_selectors: DKIM_SELECTORS, spf_cname_prefix: SPF_CNAME_PREFIX, spf_cname_target: SPF_CNAME_TARGET)
          @dkim_selectors   = dkim_selectors
          @spf_cname_prefix = spf_cname_prefix
          @spf_cname_target = spf_cname_target
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
              value: "#{selector}.dkim.lettermint.com",
              purpose: "DKIM signature #{i + 1} of #{@dkim_selectors.size}",
            }
          end

          # SPF/Return-Path CNAME record (Lettermint maintains SPF at the target)
          records << {
            type: 'CNAME',
            host: "#{@spf_cname_prefix}.#{domain}",
            value: @spf_cname_target,
            purpose: 'SPF/Return-Path (bounce handling)',
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
