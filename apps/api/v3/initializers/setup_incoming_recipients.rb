# apps/api/v3/initializers/setup_incoming_recipients.rb
#
# frozen_string_literal: true

require 'digest/sha2'

module Onetime
  module Initializers
    # SetupIncomingRecipients initializer
    #
    # Sets up recipient hashing for the incoming secrets feature.
    # Processes raw email addresses from config and creates:
    # 1. A lookup table mapping hashes to emails (for backend)
    # 2. Public recipient list with hashes only (for frontend)
    #
    # This prevents email addresses from being exposed in API responses
    # while still allowing the backend to send notifications.
    #
    # Runtime state set:
    # - Onetime.incoming_recipient_lookup
    # - Onetime.incoming_public_recipients
    #
    class SetupIncomingRecipients < Onetime::Boot::Initializer
      @provides = [:incoming_recipients]
      @optional = true

      def should_skip?
        !OT.conf.dig('features', 'incoming', 'enabled')
      end

      def execute(_context)
        raw_recipients = OT.conf.dig('features', 'incoming', 'recipients') || []

        # Create lookup tables
        recipient_lookup  = {}
        public_recipients = []

        # Validate site secret before processing recipients.
        # A missing secret would cause all recipient hashes to be computed with
        # a predictable fallback, allowing offline enumeration of recipient hashes.
        site_secret = OT.conf.dig('site', 'secret')
        if site_secret.nil? || site_secret.to_s.strip.empty?
          raise OT::Problem, '[IncomingSecrets] site.secret must be configured before enabling incoming secrets'
        end

        raw_recipients.each do |recipient|
          # Skip nil entries (from unset env vars)
          next if recipient.nil?

          # Handle both formats:
          # - Array: ["email", "name"] or ["email"] (from env vars)
          # - Hash: { email: "...", name: "..." } (from YAML)
          if recipient.is_a?(Array)
            next if recipient.empty? || recipient[0].to_s.strip.empty?

            email = recipient[0].to_s.strip
            name  = recipient[1]&.strip || email.split('@').first
          else
            # Handle both symbol and string keys (config may use either)
            email = recipient[:email] || recipient['email']
            name  = recipient[:name] || recipient['name'] || email.to_s.split('@').first
          end

          next if email.to_s.empty?

          # Generate a hash for this email
          # Use site secret as salt for consistency within process lifetime
          hash_key = Digest::SHA256.hexdigest("#{email}:#{site_secret}")

          # Store for backend lookup
          recipient_lookup[hash_key] = email

          # Store for frontend display (without email)
          public_recipients << {
            'hash' => hash_key,
            'name' => name,
          }

          OT.info "[IncomingSecrets] Registered recipient: #{name} (#{OT::Utils.obscure_email(email)}) [#{hash_key[0..7]}...]"
        end

        # Store in class instance variables for quick access
        Onetime.instance_variable_set(:@incoming_recipient_lookup, recipient_lookup.freeze)
        Onetime.instance_variable_set(:@incoming_public_recipients, public_recipients.freeze)

        OT.info "[IncomingSecrets] Initialized #{recipient_lookup.size} recipients"
      end
    end
  end
end

# Module methods for accessing incoming recipient data
module Onetime
  class << self
    # Returns the lookup table mapping hashes to email addresses
    # @return [Hash<String, String>] Hash mapping recipient hashes to emails
    def incoming_recipient_lookup
      @incoming_recipient_lookup || {}
    end

    # Returns the public recipients list (hashes and names only, no emails)
    # @return [Array<Hash>] Array of hashes with 'hash' and 'name' keys
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
