# lib/onetime/mail/views/sso_link_verification.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # SSO link verification (mailbox-proof linking) email template (#3840 Phase 4).
      #
      # Sent when an UNAUTHENTICATED SSO sign-in matches an EXISTING PASSWORDLESS
      # account. Delivered to the account's ON-FILE address; clicking the link proves
      # mailbox control and binds the SSO identity. The consent copy NAMES the
      # requesting provider AND the claimed email (criterion 2) so the recipient can
      # tell exactly what they are authorizing.
      #
      # Required data:
      #   email_address: On-file account email (recipient + claimed-email echo)
      #   confirm_url:   Full URL of the SPA confirm page (carries the single-use token)
      #   provider:      OmniAuth provider name that initiated the sign-in
      #
      # Optional data:
      #   baseuri:        Override site base URI
      #   product_name:   Override product name
      #   display_domain: Override display domain
      #
      class SsoLinkVerification < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Confirm URL required' unless data[:confirm_url]
          raise ArgumentError, 'Provider required' unless data[:provider]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.sso_link_verification.subject',
            locale: locale,
            provider: provider,
            product_name: product_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def confirm_url
          data[:confirm_url]
        end

        def provider
          data[:provider]
        end

        def email_address
          data[:email_address]
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            confirm_url: confirm_url,
            provider: provider,
            email_address: email_address,
            baseuri: baseuri,
            product_name: product_name,
            display_domain: display_domain,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
