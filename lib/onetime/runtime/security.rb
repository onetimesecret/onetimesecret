# lib/onetime/runtime/security.rb
#
# frozen_string_literal: true

module Onetime
  module Runtime
    # Security-related runtime state
    #
    # Holds encryption secrets and security configuration set during boot.
    # This state is immutable after initialization and thread-safe.
    #
    # Set by: SetSecrets initializer
    #
    Security = Data.define(
      :global_secret,      # Main encryption secret for the application
    ) do
      # Factory method for default state
      #
      # @return [Security] Security state with safe defaults
      #
      def self.default
        new(
          global_secret: nil,
        )
      end

      # Check if secrets are configured
      #
      # @return [Boolean] true if global secret is set
      #
      def configured?
        !global_secret.nil? && !global_secret.empty?
      end
    end
  end
end
