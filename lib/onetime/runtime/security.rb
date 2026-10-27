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
    # Set by: SetSecrets initializer (global_secret), SetupPasetoKeys
    # initializer (paseto_keyring)
    #
    Security = Data.define(
      :global_secret,      # Main encryption secret for the application
      :paseto_keyring,     # Onetime::Paseto::Keyring derived from the secret (#2427)
    ) do
      # Every member defaults to nil so an initializer that sets one field
      # (SetSecrets builds a fresh Security with only global_secret) does not
      # have to know about the others. Fields set by later initializers are
      # merged in through Runtime.update_security.
      def initialize(global_secret: nil, paseto_keyring: nil)
        super
      end

      # Factory method for default state
      #
      # @return [Security] Security state with safe defaults
      #
      def self.default
        new
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
