# lib/onetime/models/custom_domain/incoming_secrets_config.rb
#
# frozen_string_literal: true

require 'digest/sha2'
require 'json'

module Onetime
  class CustomDomain
    # Configuration for per-domain incoming secrets, stored as a JSON blob
    # in the CustomDomain jsonkey :incoming_secrets.
    #
    # Recipients are one level of settings in this blob, alongside
    # memo_max_length, default_ttl, etc.
    #
    # Follows the caboose jsonkey pattern on Organization.
    #
    # @example JSON blob structure
    #   {
    #     "recipients": [
    #       {"email": "support@example.com", "name": "Support Team"},
    #       {"email": "admin@example.com", "name": "Admin"}
    #     ],
    #     "memo_max_length": 50,
    #     "default_ttl": 604800
    #   }
    #
    # @example Usage
    #   config = custom_domain.incoming_secrets_config
    #   config.has_incoming_recipients?        # => true
    #   config.public_incoming_recipients(secret)  # => [{hash:, name:}, ...]
    #   config.lookup_incoming_recipient(hash, secret)  # => "email@example.com"
    #
    class IncomingSecretsConfig
      DEFAULTS = {
        memo_max_length: 50,
        default_ttl: 604_800,
      }.freeze

      MAX_RECIPIENTS  = 20
      MAX_NAME_LENGTH = 100

      attr_reader :recipients, :memo_max_length, :default_ttl

      # Parse from JSON string (as stored in Redis jsonkey)
      #
      # @param json_str [String, nil] JSON string from Redis
      # @return [IncomingSecretsConfig] Parsed config
      def self.from_json(json_str)
        return new({}) if json_str.to_s.empty?

        new(JSON.parse(json_str))
      rescue JSON::ParserError => ex
        OT.le "[IncomingSecretsConfig] Corrupted JSON in Redis, returning empty config: #{ex.message}"
        new({})
      end

      def initialize(data)
        data             = (data || {}).transform_keys(&:to_s)
        @recipients      = parse_recipients(data['recipients'])
        @memo_max_length = normalize_positive_int(data['memo_max_length'], DEFAULTS[:memo_max_length])
        @default_ttl     = normalize_positive_int(data['default_ttl'], DEFAULTS[:default_ttl])
      end

      # Serialize to JSON for Redis storage
      #
      # @return [String] JSON string
      def to_json(*)
        {
          recipients: recipients.map { |r| { email: r[:email], name: r[:name] } },
          memo_max_length: memo_max_length,
          default_ttl: default_ttl,
        }.to_json
      end

      # Returns hashed recipients for frontend display (no emails exposed).
      # Same hashing scheme as global SetupIncomingRecipients initializer.
      #
      # @param site_secret [String] Site secret used as hash salt
      # @return [Array<Hash>] Array of {digest:, display_name:} hashes
      def public_incoming_recipients(site_secret)
        recipients.map do |r|
          hash_key = Digest::SHA256.hexdigest("#{r[:email]}:#{site_secret}")
          { 'digest' => hash_key, 'display_name' => r[:name] }
        end
      end

      # Returns {hash => email} mapping for backend validation
      #
      # Memoized per site_secret since recipients is frozen and immutable.
      #
      # @param site_secret [String] Site secret used as hash salt
      # @return [Hash<String, String>] Hash mapping recipient hashes to emails
      def incoming_recipient_lookup(site_secret)
        @incoming_recipient_lookup              ||= {}
        @incoming_recipient_lookup[site_secret] ||= recipients.each_with_object({}) do |r, lookup|
          hash_key         = Digest::SHA256.hexdigest("#{r[:email]}:#{site_secret}")
          lookup[hash_key] = r[:email]
        end
      end

      # Look up a single email by recipient hash
      #
      # @param hash_key [String] The recipient hash
      # @param site_secret [String] Site secret used as hash salt
      # @return [String, nil] Email address if found, nil otherwise
      def lookup_incoming_recipient(hash_key, site_secret)
        incoming_recipient_lookup(site_secret)[hash_key]
      end

      # @return [Boolean] Whether any recipients are configured
      # rubocop:disable Naming/PredicatePrefix
      def has_incoming_recipients?
        !recipients.empty?
      end
      # rubocop:enable Naming/PredicatePrefix

      # Replace the recipients list
      #
      # @param recipients_array [Array<Hash>] Array of {email:, name:} hashes
      # @return [self] For chaining
      def set_incoming_recipients(recipients_array)
        @recipients = parse_recipients(recipients_array)
        self
      end

      # Remove all recipients
      #
      # @return [self] For chaining
      def clear_incoming_recipients
        @recipients = [].freeze
        self
      end

      private

      # Coerce value to a positive integer, falling back to default if invalid.
      # Handles strings, nil, negative values, zero, and non-numeric types.
      #
      # @param value [Object] The value to coerce
      # @param default [Integer] Fallback if coercion fails or result is non-positive
      # @return [Integer] A positive integer
      def normalize_positive_int(value, default)
        int_val = value.to_i
        int_val > 0 ? int_val : default
      end

      def parse_recipients(raw)
        return [].freeze unless raw.is_a?(Array)

        raw.filter_map do |r|
          # Defensive: skip non-Hash entries (corrupted data, nil, strings, etc.)
          next unless r.is_a?(Hash)

          r     = r.transform_keys(&:to_s)
          email = r['email'].to_s.strip.downcase
          next if email.empty?

          # Coerce name to string defensively (handles nil, non-string values)
          name = r['name'].to_s.strip
          name = email.split('@').first if name.empty?
          name = name.slice(0, MAX_NAME_LENGTH)
          { email: email, name: name }
        end.take(MAX_RECIPIENTS).freeze
      end
    end
  end
end
