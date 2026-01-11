# lib/onetime/mail/mailer.rb
#
# frozen_string_literal: true

require_relative 'delivery/base'
require_relative 'delivery/logger'
require_relative 'delivery/smtp'
require_relative 'delivery/ses'
require_relative 'delivery/sendgrid'
require_relative 'templates/base'
require_relative 'templates/secret_link'
require_relative 'templates/welcome'
require_relative 'templates/password_request'
require_relative 'templates/incoming_secret'
require_relative 'templates/feedback_email'
require_relative 'templates/secret_revealed'
require_relative 'templates/expiration_warning'
require_relative 'templates/organization_invitation'
require_relative 'templates/magic_link'

module Onetime
  module Mail
    # Unified mailer for Onetime Secret.
    #
    # Provides a simple interface for sending emails with support for
    # multiple delivery backends (SMTP, SES, SendGrid) and ERB templates.
    #
    # Configuration is determined from:
    #   1. OT.conf['emailer'] settings
    #   2. Environment variables (fallback)
    #
    # Example usage:
    #   # Send a secret link email
    #   Onetime::Mail::Mailer.deliver(:secret_link,
    #     secret: secret_obj,
    #     recipient: "user@example.com",
    #     sender_email: "sender@example.com"
    #   )
    #
    #   # Using template class directly
    #   template = Onetime::Mail::Templates::SecretLink.new(
    #     secret: secret,
    #     recipient: "user@example.com",
    #     sender_email: "sender@example.com"
    #   )
    #   Onetime::Mail::Mailer.deliver_template(template)
    #
    class Mailer
      class << self
        # Deliver an email using a named template
        # @param template_name [Symbol] Template name (:secret_link, :welcome, etc.)
        # @param data [Hash] Template data
        # @param locale [String] Locale code (default: 'en')
        # @return [Object] Delivery response
        def deliver(template_name, data = {}, locale: 'en')
          template_class = template_class_for(template_name)
          template       = template_class.new(data, locale: locale)
          deliver_template(template)
        end

        # Deliver an email using a template instance
        # @param template [Templates::Base] Template instance
        # @return [Object] Delivery response
        def deliver_template(template)
          email = template.to_email(
            from: from_address,
            reply_to: reply_to_address(template),
          )
          delivery_backend.deliver(email)
        end

        # Deliver a raw email hash (for Rodauth integration)
        # @param email [Hash] Email with :to, :from, :subject, :body keys
        # @return [Object] Delivery response
        def deliver_raw(email)
          # Normalize the email format
          normalized = {
            to: extract_email_address(email[:to]),
            from: extract_email_address(email[:from]) || from_address,
            reply_to: email[:reply_to]&.to_s,
            subject: email[:subject]&.to_s,
            text_body: email[:body]&.to_s,
            html_body: email[:html_body]&.to_s,
          }
          delivery_backend.deliver(normalized)
        end

        # Get the configured delivery backend
        # @return [Delivery::Base]
        def delivery_backend
          @delivery_backend ||= create_delivery_backend
        end

        # Reset the delivery backend (useful for testing)
        def reset!
          @delivery_backend = nil
        end

        # Get the configured from address
        # @return [String]
        def from_address
          conf = emailer_config
          conf['from'] || ENV['EMAIL_FROM'] || 'noreply@example.com'
        end

        # Get the configured from name
        # @return [String, nil]
        def from_name
          conf = emailer_config
          if conf['from_name']
            conf['from_name']
          elsif conf['fromname']
            log_info "[mail] DEPRECATION: 'fromname' config is deprecated since v0.23, use 'from_name' instead"
            conf['fromname']
          end
        end

        private

        def template_class_for(name)
          case name.to_sym
          when :secret_link
            Templates::SecretLink
          when :welcome
            Templates::Welcome
          when :password_request
            Templates::PasswordRequest
          when :incoming_secret
            Templates::IncomingSecret
          when :feedback_email
            Templates::FeedbackEmail
          when :secret_revealed
            Templates::SecretRevealed
          when :expiration_warning
            Templates::ExpirationWarning
          when :organization_invitation
            Templates::OrganizationInvitation
          else
            raise ArgumentError, "Unknown template: #{name}"
          end
        end

        def create_delivery_backend
          provider = determine_provider
          config   = build_provider_config(provider)

          log_info "[mail] Using #{provider} delivery backend"

          case provider
          when 'smtp'
            Delivery::SMTP.new(config)
          when 'ses'
            Delivery::SES.new(config)
          when 'sendgrid'
            Delivery::SendGrid.new(config)
          when 'logger'
            Delivery::Logger.new(config)
          else
            log_error "[mail] Unknown provider '#{provider}', falling back to logger"
            Delivery::Logger.new(config)
          end
        rescue ArgumentError => ex
          log_error "[mail] Configuration error: #{ex.message}, falling back to logger"
          Delivery::Logger.new({})
        end

        # Logging helpers that work with or without OT defined
        def log_info(message)
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        def log_error(message)
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        def determine_provider
          conf = emailer_config
          mode = conf['mode']&.to_s&.downcase

          return mode if mode && !mode.empty?

          # Test environment always uses logger
          return 'logger' if ENV['RACK_ENV'] == 'test'

          # Auto-detect based on configuration
          if conf['region'] && conf['user']
            'ses' # AWS SES uses region + AWS credentials
          elsif conf['sendgrid_api_key']
            'sendgrid'
          elsif conf['host']
            'smtp'
          else
            'logger' # fallback
          end
        end

        def build_provider_config(provider)
          conf = emailer_config

          case provider
          when 'smtp'
            {
              host: conf['host'] || ENV.fetch('SMTP_HOST', nil),
              port: conf['port'] || ENV.fetch('SMTP_PORT', nil),
              username: conf['user'] || ENV.fetch('SMTP_USERNAME', nil),
              password: conf['pass'] || ENV.fetch('SMTP_PASSWORD', nil),
              domain: conf['domain'] || ENV.fetch('SMTP_DOMAIN', nil),
              tls: conf['tls'],
            }
          when 'ses'
            {
              region: conf['region'] || ENV.fetch('AWS_REGION', nil),
              access_key_id: conf['user'] || ENV.fetch('AWS_ACCESS_KEY_ID', nil),
              secret_access_key: conf['pass'] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil),
            }
          when 'sendgrid'
            {
              api_key: conf['sendgrid_api_key'] || conf['pass'] || ENV.fetch('SENDGRID_API_KEY', nil),
            }
          else
            {}
          end
        end

        def emailer_config
          return {} unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf['emailer'] || OT.conf[:emailer] || {}
        end

        def reply_to_address(template)
          # Some templates may have a specific reply-to
          template.data[:reply_to] || template.data[:sender_email]
        end

        def extract_email_address(value)
          return nil if value.nil?

          if value.respond_to?(:first)
            value.first&.to_s
          else
            value.to_s
          end
        end
      end
    end
  end
end
