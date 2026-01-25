# lib/onetime/mail.rb
#
# frozen_string_literal: true

# Unified email system for Onetime Secret.
#
# Supports multiple delivery backends:
#   - SMTP (via mail gem)
#   - AWS SES (via aws-sdk-sesv2)
#   - SendGrid (via REST API)
#   - Logger (for development/testing)
#
# Templates use ERB and support both text and HTML formats.
# Designed for future ruby-i18n integration.
#
# Configuration is read from OT.conf['emailer'] or environment variables.
#
# Example config (etc/config.yaml):
#   emailer:
#     mode: smtp  # smtp, ses, sendgrid, or logger
#     from: noreply@example.com
#     from_name: Onetime Secret
#     host: smtp.example.com
#     port: 587
#     user: username
#     pass: password
#     tls: true
#
# Example usage:
#   require 'onetime/mail'
#
#   # Send using named template
#   Onetime::Mail::Mailer.deliver(:secret_link,
#     secret: secret,
#     recipient: "user@example.com",
#     sender_email: "sender@example.com"
#   )
#
#   # Or use template class directly
#   template = Onetime::Mail::Templates::SecretLink.new(...)
#   Onetime::Mail::Mailer.deliver_template(template)
#
require_relative 'mail/mailer'

module Onetime
  module Mail
    # Exception raised when email delivery fails.
    # Used to distinguish mail-specific errors from other failures
    # and enable appropriate retry/rejection logic in workers.
    class DeliveryError < StandardError
      attr_reader :original_error, :transient

      # @param message [String] Error message
      # @param original_error [Exception, nil] The underlying error
      # @param transient [Boolean] Whether the error is likely transient (retry-able)
      def initialize(message, original_error: nil, transient: false)
        super(message)
        @original_error = original_error
        @transient      = transient
      end

      def transient?
        @transient
      end
    end

    # Convenience method for delivering emails
    # @see Mailer.deliver
    def self.deliver(template_name, data = {}, locale: 'en')
      Mailer.deliver(template_name, data, locale: locale)
    end

    # Convenience method for delivering raw emails
    # @see Mailer.deliver_raw
    def self.deliver_raw(email)
      Mailer.deliver_raw(email)
    end
  end
end
