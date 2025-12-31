# lib/onetime/mail/templates/welcome.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Welcome/verification email template for new users.
      #
      # Required data:
      #   email_address: User's email address
      #   secret:        Secret object containing verification token
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class Welcome < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Secret required' unless data[:secret]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.welcome.subject',
            locale: locale,
            product_name: product_name,
          )
        end

        def product_name
          data[:product_name] || site_product_name
        end

        def site_product_name
          return 'Onetime Secret' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'product_name') || 'Onetime Secret'
        end

        def recipient_email
          data[:email_address]
        end

        def verify_uri
          secret = data[:secret]
          key    = secret.respond_to?(:identifier) ? secret.identifier : secret.to_s
          "/secret/#{key}"
        end

        def email_address
          data[:email_address]
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def site_ssl?
          return true unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'ssl') != false
        end

        def site_host
          return 'onetimesecret.com' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'host') || 'onetimesecret.com'
        end

        def site_baseuri
          scheme = site_ssl? ? 'https://' : 'http://'
          "#{scheme}#{site_host}"
        end

        def template_binding
          computed_data = data.merge(
            verify_uri: verify_uri,
            email_address: email_address,
            baseuri: baseuri,
            product_name: product_name,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
