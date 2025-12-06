# lib/onetime/mail/templates/secret_link.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for sharing a secret link with a recipient.
      #
      # Required data:
      #   secret_key:   Secret key for URL (string)
      #   recipient:    Recipient email address
      #   sender_email: Sender's email address (shown in email body)
      #
      # Optional data:
      #   share_domain: Custom domain for secret sharing
      #   baseuri:      Override site base URI
      #
      # NOTE: Uses primitive data types for RabbitMQ serialization.
      # Secret objects cannot be serialized to JSON.
      #
      class SecretLink < Base
        protected

        def validate_data!
          raise ArgumentError, 'Secret key required' unless data[:secret_key]
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          raise ArgumentError, 'Sender email required' unless data[:sender_email]
        end

        public

        def subject
          # TODO: I18n.t('email.secret_link.subject', sender: data[:sender_email])
          "#{data[:sender_email]} sent you a secret"
        end

        def recipient_email
          data[:recipient]
        end

        # Computed template variables
        def display_domain
          scheme = site_ssl? ? 'https://' : 'http://'
          host   = data[:share_domain].to_s.empty? ? site_host : data[:share_domain]
          "#{scheme}#{host}"
        end

        def uri_path
          "/secret/#{data[:secret_key]}"
        end

        def custid
          data[:sender_email]
        end

        def signature_link
          site_baseuri
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

        # Override to include computed values in template context
        def template_binding
          computed_data = data.merge(
            display_domain: display_domain,
            uri_path: uri_path,
            custid: custid,
            signature_link: signature_link,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
