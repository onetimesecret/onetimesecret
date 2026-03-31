# lib/onetime/domain_validation/sender_strategies/sendgrid_validation.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    module SenderStrategies
      # SendgridValidation - SendGrid sender domain validation strategy.
      #
      # SendGrid domain authentication requires:
      #   - 3 CNAME records for DKIM (s1, s2 selectors + mail CNAME for link branding)
      #   - 1 TXT record for SPF alignment
      #
      # The DKIM CNAME records point to SendGrid's infrastructure via a
      # subdomain label. By default SendGrid uses "em" + a numeric suffix
      # as the branding subdomain, but customers can customize this.
      #
      # Reference: https://docs.sendgrid.com/ui/account-and-settings/how-to-set-up-domain-authentication
      #
      class SendgridValidation < BaseStrategy
        # Legacy constants preserved for backward compatibility.
        # New code should rely on ProviderConfig defaults.
        DKIM_SELECTORS    = %w[s1 s2].freeze
        SPF_INCLUDE       = 'sendgrid.net'
        DEFAULT_SUBDOMAIN = 'em'

        def self.accepted_options
          [:subdomain, :dkim_selectors, :spf_include].freeze
        end

        # @param subdomain [String] SendGrid branding subdomain (default from config or 'em')
        # @param dkim_selectors [Array<String>] DKIM selector names (default: ['s1', 's2'])
        # @param spf_include [String] SPF include domain (default: 'sendgrid.net')
        def initialize(subdomain: DEFAULT_SUBDOMAIN, dkim_selectors: DKIM_SELECTORS, spf_include: SPF_INCLUDE)
          @subdomain      = subdomain
          @dkim_selectors = dkim_selectors
          @spf_include    = spf_include
        end

        # Returns the DNS records required for SendGrid domain authentication.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def required_dns_records(mailer_config)
          domain = resolve_domain(mailer_config)

          records = []

          # DKIM CNAME records (configurable selectors, default s1, s2)
          @dkim_selectors.each_with_index do |selector, i|
            records << {
              type: 'CNAME',
              host: "#{selector}._domainkey.#{domain}",
              value: "#{selector}.domainkey.#{@subdomain}.#{domain}.#{@spf_include}",
              purpose: "DKIM signature #{i + 1} of #{@dkim_selectors.size}",
            }
          end

          # Link branding / return-path CNAME
          records << {
            type: 'CNAME',
            host: "#{@subdomain}.#{domain}",
            value: "u.#{@spf_include}",
            purpose: 'SendGrid link branding and return-path',
          }

          # SPF TXT record
          records << {
            type: 'TXT',
            host: domain,
            value: "v=spf1 include:#{@spf_include} ~all",
            purpose: 'SPF authentication',
          }

          records
        end

        # Verifies SendGrid DNS records via live DNS lookup.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def verify_dns_records(mailer_config)
          verify_all_records(mailer_config)
        end

        # @return [String]
        def strategy_name
          'sendgrid'
        end
      end
    end
  end
end
