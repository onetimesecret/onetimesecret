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
        DKIM_SELECTORS    = %w[s1 s2].freeze
        SPF_INCLUDE       = 'sendgrid.net'
        DEFAULT_SUBDOMAIN = 'em'

        def self.accepted_options
          [:subdomain].freeze
        end

        # @param subdomain [String] SendGrid branding subdomain (default: "em")
        def initialize(subdomain: DEFAULT_SUBDOMAIN)
          @subdomain = subdomain
        end

        # Returns the DNS records required for SendGrid domain authentication.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>]
        #
        def required_dns_records(mailer_config)
          domain = resolve_domain(mailer_config)

          records = []

          # DKIM CNAME records (s1, s2 selectors)
          DKIM_SELECTORS.each_with_index do |selector, i|
            records << {
              type: 'CNAME',
              host: "#{selector}._domainkey.#{domain}",
              value: "#{selector}.domainkey.#{@subdomain}.#{domain}.#{SPF_INCLUDE}",
              purpose: "DKIM signature #{i + 1} of #{DKIM_SELECTORS.size}",
            }
          end

          # Link branding / return-path CNAME
          records << {
            type: 'CNAME',
            host: "#{@subdomain}.#{domain}",
            value: "u.#{SPF_INCLUDE}",
            purpose: 'SendGrid link branding and return-path',
          }

          # SPF TXT record
          records << {
            type: 'TXT',
            host: domain,
            value: "v=spf1 include:#{SPF_INCLUDE} ~all",
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
