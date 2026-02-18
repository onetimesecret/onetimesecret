# lib/onetime/mail/delivery/base.rb
#
# frozen_string_literal: true

require 'openssl'

module Onetime
  module Mail
    module Delivery
      # Abstract base class for email delivery backends.
      # Subclasses implement provider-specific delivery logic.
      #
      # All backends accept a standardized email hash:
      #   {
      #     to: "recipient@example.com",
      #     from: "sender@example.com",
      #     reply_to: "reply@example.com",  # optional
      #     subject: "Email subject",
      #     text_body: "Plain text content",
      #     html_body: "<html>...</html>"    # optional
      #   }
      #
      class Base
        attr_reader :config

        # Network errors common across all providers
        NETWORK_ERRORS = [
          Errno::ECONNREFUSED,
          Errno::ECONNRESET,
          Errno::ETIMEDOUT,
          Net::OpenTimeout,
          Net::ReadTimeout,
          IOError,
          SocketError,
          OpenSSL::SSL::SSLError,
        ].freeze

        def initialize(config = {})
          @config = config
          validate_config!
        end

        # Deliver an email message with unified error handling.
        # Subclasses implement perform_delivery and classify_error.
        # @param email [Hash] Email parameters (to, from, subject, text_body, html_body)
        # @return [Object] Provider-specific response or nil
        def deliver(email)
          email  = normalize_email(email)
          result = perform_delivery(email)
          log_delivery(email, delivery_log_status)
          result
        rescue Onetime::Mail::DeliveryError
          raise # pass-through, no double-wrap
        rescue StandardError => ex
          log_error(email, ex)
          transient = classify_error(ex) == :transient
          raise Onetime::Mail::DeliveryError.new(
            "#{provider_name} delivery error: #{ex.message}",
            original_error: ex,
            transient: transient,
          )
        end

        # Subclass hook: provider-specific send logic
        # @param email [Hash] Normalized email parameters
        # @return [Object] Provider-specific response
        def perform_delivery(email)
          raise NotImplementedError, "#{self.class} must implement #perform_delivery"
        end

        # Subclass hook: classify provider-specific errors.
        # Returns :transient, :fatal, or :unknown.
        # :unknown defaults to non-transient (fail fast).
        # @param error [StandardError] The error to classify
        # @return [Symbol] :transient, :fatal, or :unknown
        def classify_error(error)
          return :transient if NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }

          :unknown
        end

        # Override in subclasses to change the log status label
        # @return [String]
        def delivery_log_status
          'sent'
        end

        # Provider name for logging
        # @return [String]
        def provider_name
          self.class.name.split('::').last
        end

        protected

        # Override in subclasses for provider-specific validation
        def validate_config!
          # Base implementation does nothing
        end

        def log_delivery(email, status = 'sent')
          obscured = obscure_email(email[:to])
          message  = "[mail] #{status.capitalize} via #{provider_name} to #{obscured}: #{email[:subject]}"
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        def log_error(email, error)
          obscured = obscure_email(email[:to])
          message  = "[mail] Delivery failed via #{provider_name} to #{obscured}: #{error.message}"
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        # Obscure email address for logging
        def obscure_email(email)
          return email if email.to_s.empty?

          # Try to use OT::Utils if available
          if defined?(OT::Utils) && OT::Utils.respond_to?(:obscure_email)
            OT::Utils.obscure_email(email)
          else
            # Simple fallback obscuring
            parts          = email.to_s.split('@')
            return email if parts.length != 2

            local          = parts[0]
            domain         = parts[1]
            obscured_local = local.length > 2 ? "#{local[0..1]}***" : '***'
            "#{obscured_local}@#{domain}"
          end
        end

        # Normalize email hash to ensure required fields
        def normalize_email(email)
          {
            to: email[:to].to_s,
            from: email[:from].to_s,
            reply_to: email[:reply_to]&.to_s,
            subject: email[:subject].to_s,
            text_body: email[:text_body].to_s,
            html_body: email[:html_body]&.to_s,
          }
        end

        # Check if we have HTML content
        def html_content?(email)
          !email[:html_body].to_s.empty?
        end
      end
    end
  end
end
