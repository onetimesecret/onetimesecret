# lib/onetime/runtime/email.rb
#
# frozen_string_literal: true

module Onetime
  module Runtime
    # Email validation runtime state
    #
    # Holds email validation configuration set during boot. This state is
    # immutable after initialization and thread-safe.
    #
    # Set by: ConfigureTruemail initializer
    #
    Email = Data.define(
      :truemail_configured,   # Whether Truemail email validation is configured
    ) do
      # Factory method for default state
      #
      # @return [Email] Email state with safe defaults
      #
      def self.default
        new(
          truemail_configured: false,
        )
      end

      # Check if email validation is configured
      #
      # @return [Boolean] true if Truemail is configured
      #
      def configured?
        truemail_configured
      end
    end
  end
end
