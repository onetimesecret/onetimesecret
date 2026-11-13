# lib/onetime/mail/errors.rb
#
# frozen_string_literal: true

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

    # Exception raised when the install's delivery backend cannot be built
    # from its configuration: a missing SMTP host, missing provider
    # credentials, an unrecognized setting. It says nothing about the message
    # being sent. Every message fails the same way until the configuration is
    # fixed and the process restarts, so callers must not treat it as a
    # malformed message (ArgumentError) or as a provider's response to one
    # message (DeliveryError).
    #
    # Raised from the backends' validate_config!, and by
    # Mailer.create_delivery_backend for a config-shaped error raised while
    # the backend is built.
    class ConfigurationError < StandardError
      # @return [String, nil] lowercase transport name, e.g. 'smtp', 'ses'
      attr_reader :provider

      # @param message [String] what is wrong with the configuration
      # @param provider [String, nil] the transport the backend is built for
      def initialize(message = nil, provider: nil)
        super(message)
        @provider = provider
      end
    end
  end
end
