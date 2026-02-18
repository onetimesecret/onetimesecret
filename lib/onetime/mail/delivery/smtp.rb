# lib/onetime/mail/delivery/smtp.rb
#
# frozen_string_literal: true

require 'mail'
require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # SMTP delivery backend using the mail gem.
      # Supports multipart text/HTML emails with TLS.
      #
      # Configuration options (via config hash or ENV):
      #   host:     SMTP server hostname (ENV: SMTP_HOST)
      #   port:     SMTP port (ENV: SMTP_PORT, default: 587)
      #   username: SMTP username (ENV: SMTP_USERNAME)
      #   password: SMTP password (ENV: SMTP_PASSWORD)
      #   tls:      Enable STARTTLS (ENV: SMTP_TLS, default: true)
      #   domain:   HELO domain (ENV: SMTP_DOMAIN)
      #
      class SMTP < Base
        # Transient errors: network/connection issues that may resolve on retry
        TRANSIENT_ERRORS = [
          Errno::ECONNREFUSED,
          Errno::ECONNRESET,
          Errno::ETIMEDOUT,
          Net::OpenTimeout,
          Net::ReadTimeout,
          Net::SMTPServerBusy,       # 4xx: temporary server issue
          IOError,
          SocketError,
        ].freeze

        # Fatal errors: configuration or policy issues that won't resolve on retry
        FATAL_ERRORS = [
          Net::SMTPAuthenticationError,  # 535: bad credentials
          Net::SMTPFatalError,           # 5xx: permanent rejection
          Net::SMTPSyntaxError,          # 500: malformed command
          Net::SMTPUnknownError,         # unexpected response
        ].freeze

        def perform_delivery(email)
          settings = smtp_settings

          OT.ld "[smtp] Delivering to #{OT::Utils.obscure_email(email[:to])} via #{settings[:address]}:#{settings[:port]}"

          mail_message = build_mail_message(email)

          begin
            deliver_with_settings(mail_message, settings)
          rescue Net::SMTPAuthenticationError => ex
            raise unless config[:allow_unauthenticated_fallback]

            handle_auth_failure(mail_message, settings, ex)
          end

          mail_message
        end

        def classify_error(error)
          return :transient if TRANSIENT_ERRORS.any? { |klass| error.is_a?(klass) }
          return :fatal if FATAL_ERRORS.any? { |klass| error.is_a?(klass) }

          super # Base's network error check + :unknown fallback
        end

        protected

        def validate_config!
          host = config[:host] || ENV.fetch('SMTP_HOST', nil)
          raise ArgumentError, 'SMTP host must be configured' if host.nil? || host.empty?
        end

        private

        def build_mail_message(email)
          text_content  = email[:text_body]
          html_content  = email[:html_body]
          reply_to_addr = email[:reply_to]

          ::Mail.new do
            from    email[:from]
            to      email[:to]
            subject email[:subject]

            # Set reply-to if provided
            reply_to reply_to_addr if reply_to_addr && !reply_to_addr.empty?

            # Build multipart message if we have HTML
            if html_content && !html_content.empty?
              text_part do
                content_type 'text/plain; charset=UTF-8'
                body text_content
              end

              html_part do
                content_type 'text/html; charset=UTF-8'
                body html_content
              end
            else
              # Text-only email
              content_type 'text/plain; charset=UTF-8'
              body text_content
            end
          end
        end

        def deliver_with_settings(mail, settings)
          mail.delivery_method :smtp, settings
          mail.deliver!

          OT.ld "[smtp] Delivery successful to #{settings[:address]}:#{settings[:port]}"
        end

        def handle_auth_failure(mail, settings, error)
          OT.info "[smtp] Auth failed, retrying without auth: #{error.message}"

          settings_no_auth = settings.except(:user_name, :password, :authentication)
          mail.delivery_method :smtp, settings_no_auth
          mail.deliver!

          OT.ld '[smtp] Delivery successful without authentication'
        end

        def smtp_settings
          settings = {
            address: config[:host] || ENV['SMTP_HOST'] || 'localhost',
            port: (config[:port] || ENV['SMTP_PORT'] || '587').to_i,
            enable_starttls_auto: resolve_tls_setting,
          }

          # Add domain if configured
          domain            = config[:domain] || ENV.fetch('SMTP_DOMAIN', nil)
          settings[:domain] = domain if domain && !domain.empty?

          # Add authentication if credentials provided
          username = config[:username] || ENV.fetch('SMTP_USERNAME', nil)
          password = config[:password] || ENV.fetch('SMTP_PASSWORD', nil)

          if username && !username.empty? && password && !password.empty?
            settings[:user_name]      = username
            settings[:password]       = password
            settings[:authentication] = :plain
          end

          settings
        end

        def resolve_tls_setting
          return config[:tls] unless config[:tls].nil?

          ENV['SMTP_TLS'] != 'false'
        end
      end
    end
  end
end
