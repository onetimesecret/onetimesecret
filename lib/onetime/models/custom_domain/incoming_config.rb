# lib/onetime/models/custom_domain/incoming_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::IncomingConfig - Per-domain incoming secrets recipient storage
#
# This model stores incoming secrets configuration bound to a specific CustomDomain.
# When enabled, anonymous users can send encrypted secrets to pre-configured
# recipients for that domain.
#
# Use Cases:
#   - Bug bounty programs: security@acme.com receives anonymous vulnerability reports
#   - Anonymous tips: compliance@acme.com receives whistleblower reports
#   - Customer feedback: feedback@acme.com receives anonymous product feedback
#
# Recipient Hashing:
#   Recipient email addresses are hashed (SHA256 with site secret) before being
#   exposed to the frontend. This prevents enumeration attacks while still
#   allowing the backend to route secrets to the correct recipient.
#
module Onetime
  class CustomDomain < Familia::Horreum
    class IncomingConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-incoming-config'

      # Maximum number of recipients per domain
      MAX_RECIPIENTS = 20

      prefix :custom_domain__incoming_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one incoming config per domain.
      identifier_field :domain_id
      field :domain_id

      # Whether incoming secrets is enabled for this domain
      field :enabled

      # Recipients stored as JSON array of {email:, name:} objects
      # Email addresses are stored as-is; hashing happens at retrieval time
      field :recipients_json

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled         ||= 'false'
        self.recipients_json ||= '[]'
      end

      # Check if incoming secrets is enabled for this domain.
      #
      # @return [Boolean] true if incoming secrets is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Enable incoming secrets for this domain.
      # @return [void]
      def enable!
        self.enabled = 'true'
        self.updated = Familia.now.to_i
        save
      end

      # Disable incoming secrets for this domain.
      # @return [void]
      def disable!
        self.enabled = 'false'
        self.updated = Familia.now.to_i
        save
      end

      # Get the list of recipients (raw, with emails).
      #
      # @return [Array<Hash>] Array of {email:, name:} hashes
      def recipients
        return [] if recipients_json.to_s.empty?

        JSON.parse(recipients_json, symbolize_names: true)
      rescue JSON::ParserError
        []
      end

      # Set the list of recipients.
      #
      # @param recipients_array [Array<Hash>] Array of {email:, name:} hashes
      # @return [void]
      # @raise [Onetime::Problem] if validation fails
      def recipients=(recipients_array)
        normalized = normalize_recipients(recipients_array)
        validate_recipients!(normalized)

        self.recipients_json = JSON.generate(normalized)
        self.updated         = Familia.now.to_i
      end

      # Get recipients with hashed identifiers (safe for frontend).
      #
      # @return [Array<Hash>] Array of {hash:, name:} hashes
      # @raise [Onetime::Problem] if site.secret is not configured
      def public_recipients
        site_secret = require_site_secret

        recipients.map do |r|
          { hash: hash_email(r[:email], site_secret), name: r[:name] }
        end
      end

      # Look up email by recipient hash.
      #
      # @param hash [String] The recipient hash
      # @return [String, nil] Email address if found, nil otherwise
      # @raise [Onetime::Problem] if site.secret is not configured
      def lookup_recipient_email(hash)
        site_secret = require_site_secret

        recipients.find do |r|
          hash_email(r[:email], site_secret) == hash
        end&.dig(:email)
      end

      # Add a recipient.
      #
      # @param email [String] Recipient email
      # @param name [String] Recipient display name
      # @return [void]
      # @raise [Onetime::Problem] if validation fails
      def add_recipient(email:, name:)
        current = recipients
        raise Onetime::Problem, "Maximum #{MAX_RECIPIENTS} recipients allowed" if current.size >= MAX_RECIPIENTS

        normalized_email = email.to_s.strip.downcase
        raise Onetime::Problem, 'Recipient email already exists' if current.any? { |r| r[:email] == normalized_email }

        current << { email: normalized_email, name: name.to_s.strip }
        self.recipients = current
      end

      # Remove a recipient by email.
      #
      # @param email [String] Recipient email to remove
      # @return [void]
      # @raise [Onetime::Problem] if recipient not found
      def remove_recipient(email:)
        normalized_email = email.to_s.strip.downcase
        current          = recipients
        initial_size     = current.size

        current.reject! { |r| r[:email] == normalized_email }

        raise Onetime::Problem, 'Recipient not found' if current.size == initial_size

        self.recipients = current
      end

      # Clear all recipients.
      #
      # @return [void]
      def clear_recipients!
        self.recipients_json = '[]'
        self.updated         = Familia.now.to_i
        save
      end

      # Load the associated CustomDomain record.
      #
      # @return [CustomDomain, nil] The domain or nil if not found
      def custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Load the owning Organization via the CustomDomain.
      #
      # @return [Organization, nil] The organization or nil if not found
      def organization
        domain = custom_domain
        return nil unless domain

        Onetime::Organization.load(domain.org_id)
      end

      # Validate configuration.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []
        errors << 'domain_id is required' if domain_id.to_s.empty?
        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      class << self
        # Find incoming config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::IncomingConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Check if a domain has incoming config.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if incoming config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new incoming config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::IncomingConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Incoming config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          config.enabled    = attrs[:enabled].to_s if attrs.key?(:enabled)
          config.recipients = attrs[:recipients] if attrs.key?(:recipients)

          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save
          config
        end

        # Delete incoming config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          config.destroy!
          true
        end

        # List all domain incoming configs.
        #
        # @return [Array<CustomDomain::IncomingConfig>] All configs (newest first)
        def all
          instances.revrangeraw(0, -1).filter_map do |identifier|
            load(identifier)
          rescue Onetime::RecordNotFound
            nil
          end
        end

        # Count of domains with incoming config.
        #
        # @return [Integer] Number of incoming configs
        def count
          instances.size
        end
      end

      private

      # Normalize recipients array.
      #
      # @param recipients_array [Array] Raw recipients input
      # @return [Array<Hash>] Normalized recipients with symbolized keys
      def normalize_recipients(recipients_array)
        Array(recipients_array).map do |r|
          next nil unless r.is_a?(Hash)

          email = (r[:email] || r['email']).to_s.strip.downcase
          name  = (r[:name] || r['name']).to_s.strip

          next nil if email.empty?

          { email: email, name: name.empty? ? email.split('@').first : name }
        end.compact
      end

      # Validate recipients array.
      #
      # @param recipients_array [Array<Hash>] Normalized recipients
      # @raise [Onetime::Problem] if validation fails
      def validate_recipients!(recipients_array)
        raise Onetime::Problem, "Maximum #{MAX_RECIPIENTS} recipients allowed" if recipients_array.size > MAX_RECIPIENTS

        emails = recipients_array.map { |r| r[:email] }
        raise Onetime::Problem, 'Duplicate recipient emails not allowed' if emails.uniq.size != emails.size

        recipients_array.each do |r|
          unless r[:email].match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
            raise Onetime::Problem, "Invalid email format: #{r[:email]}"
          end
        end
      end

      # Compute SHA256 hash of email with site secret.
      #
      # @param email [String] Email address to hash
      # @param secret [String] Site secret for hashing
      # @return [String] Hex-encoded SHA256 hash
      def hash_email(email, secret)
        Digest::SHA256.hexdigest("#{email}:#{secret}")
      end

      # Get site secret or raise if not configured.
      #
      # @return [String] The site secret
      # @raise [Onetime::Problem] if site.secret is not configured
      def require_site_secret
        site_secret = OT.conf.dig('site', 'secret')
        raise Onetime::Problem, 'site.secret must be configured' if site_secret.to_s.empty?

        site_secret
      end
    end
  end
end
