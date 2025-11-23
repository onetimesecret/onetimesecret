# frozen_string_literal: true

require 'digest/sha2'

module Onetime
  module Initializers

    # Sets up recipient hashing for the incoming secrets feature.
    # Processes raw email addresses from config and creates:
    # 1. A lookup table mapping hashes to emails (for backend)
    # 2. Public recipient list with hashes only (for frontend)
    #
    # This prevents email addresses from being exposed in API responses
    # while still allowing the backend to send notifications.
    def setup_incoming_recipients
      return unless OT.conf.dig(:features, :incoming, :enabled)

      raw_recipients = OT.conf.dig(:features, :incoming, :recipients) || []

      # Create lookup tables
      recipient_lookup = {}
      public_recipients = []

      raw_recipients.each do |recipient|
        email = recipient[:email]
        name = recipient[:name] || email.split('@').first

        # Generate a stable hash for this email
        # Use site secret as salt to ensure consistency across restarts
        site_secret = OT.conf[:site][:secret] || 'default-secret'
        hash_key = Digest::SHA256.hexdigest("#{email}:#{site_secret}")[0..15]

        # Store for backend lookup
        recipient_lookup[hash_key] = email

        # Store for frontend display (without email)
        public_recipients << {
          hash: hash_key,
          name: name
        }

        OT.info "[IncomingSecrets] Registered recipient: #{name} (#{OT::Utils.obscure_email(email)})"
      end

      # Store in class instance variables for quick access
      OT.instance_variable_set(:@incoming_recipient_lookup, recipient_lookup.freeze)
      OT.instance_variable_set(:@incoming_public_recipients, public_recipients.freeze)

      OT.info "[IncomingSecrets] Initialized #{recipient_lookup.size} recipients"
    end

  end
end

module Onetime
  class << self

    # Returns the lookup table mapping hashes to email addresses
    # @return [Hash<String, String>] Hash mapping recipient hashes to emails
    def incoming_recipient_lookup
      @incoming_recipient_lookup || {}
    end

    # Returns the public recipients list (hashes and names only, no emails)
    # @return [Array<Hash>] Array of hashes with :hash and :name keys
    def incoming_public_recipients
      @incoming_public_recipients || []
    end

    # Look up an email address from a recipient hash
    # @param hash_key [String] The recipient hash
    # @return [String, nil] The email address if found, nil otherwise
    def lookup_incoming_recipient(hash_key)
      incoming_recipient_lookup[hash_key]
    end

  end
end
