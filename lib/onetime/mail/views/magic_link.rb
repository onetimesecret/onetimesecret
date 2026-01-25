# lib/onetime/mail/views/magic_link.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Magic link (email auth) email template.
      #
      # Sent when a user requests passwordless login via email.
      # Contains a time-limited link that authenticates the user.
      #
      # Required data:
      #   email_address: User's email address
      #   magic_link_path: Full magic link URL (from Rodauth)
      #
      # Optional data:
      #   baseuri: Override site base URI
      #   product_name: Override product name
      #   display_domain: Override display domain
      #
      class MagicLink < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Magic link path required' unless data[:magic_link_path]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.magic_link.subject',
            locale: locale,
            display_domain: display_domain,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def magic_link_url
          # Rodauth provides the full URL
          data[:magic_link_path]
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
            magic_link_url: magic_link_url,
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
