# lib/onetime/domain_validation/sender_strategies/ses_validation.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    module SenderStrategies
      # SesValidation - AWS SES sender domain validation strategy.
      #
      # AWS SES requires:
      #   - 3 CNAME records for DKIM (Easy DKIM uses three selectors)
      #   - 1 TXT record for SPF alignment
      #   - 1 MX record for inbound bounce handling
      #
      # DKIM selectors in SES are UUID-based tokens generated when you verify
      # a domain identity. Since the actual tokens are assigned by SES at
      # verification time, we use placeholder selectors that should be
      # replaced with the real values from the SES console or API response.
      #
      # Reference: https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html
      #
      class SesValidation < BaseStrategy
        # Legacy constants preserved for backward compatibility.
        # New code should rely on ProviderConfig defaults.
        DKIM_SELECTOR_COUNT = 3
        SPF_INCLUDE         = 'amazonses.com'
        DEFAULT_REGION      = 'us-east-1'

        def self.accepted_options
          [:region, :dkim_selector_count, :spf_include].freeze
        end

        # @param region [String] AWS region for MX record (default from config or 'us-east-1')
        # @param dkim_selector_count [Integer] Number of DKIM selectors (default: 3)
        # @param spf_include [String] SPF include domain (default: 'amazonses.com')
        def initialize(region: DEFAULT_REGION, dkim_selector_count: DKIM_SELECTOR_COUNT, spf_include: SPF_INCLUDE)
          @region              = region
          @dkim_selector_count = dkim_selector_count
          @spf_include         = spf_include
        end

        # Returns the DNS records required for SES domain verification.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def required_dns_records(mailer_config)
          domain = resolve_domain(mailer_config)

          records = []

          # DKIM CNAME records (configurable count, default 3)
          # SES generates unique tokens per domain; these placeholders indicate
          # the record structure. Real selectors come from the SES API response
          # when calling VerifyDomainDkim.
          @dkim_selector_count.times do |i|
            selector = "ses-dkim-token-#{i + 1}"
            records << {
              type: 'CNAME',
              host: "#{selector}._domainkey.#{domain}",
              value: "#{selector}.dkim.#{@spf_include}",
              purpose: "DKIM signature #{i + 1} of #{@dkim_selector_count}",
            }
          end

          # SPF TXT record
          records << {
            type: 'TXT',
            host: domain,
            value: "v=spf1 include:#{@spf_include} ~all",
            purpose: 'SPF authentication',
          }

          # MX record for bounce/complaint handling
          records << {
            type: 'MX',
            host: domain,
            value: "inbound-smtp.#{@region}.amazonaws.com",
            purpose: 'SES inbound mail (bounce handling)',
          }

          records
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
      end
    end
  end
end
