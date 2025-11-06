# apps/api/v2/logic/secrets/base_secret_action.rb

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class BaseSecretAction < V2::Logic::Base
      include Onetime::Logging

      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :greenlighted, :metadata,
        :secret, :share_domain, :custom_domain, :payload
      attr_accessor :token

      # Process methods populate instance variables with the values. The
      # raise_concerns and process methods deal with the values in the instance
      # variables only (no more params access).
      def process_params
        # All parameters are passed in the :secret hash (secret[:ttl], etc)
        @payload = params['secret'] || {}
        raise_form_error 'Incorrect payload format' if payload.is_a?(String)

        process_ttl
        process_secret
        process_passphrase
        process_recipient
        process_share_domain
      end

      def raise_concerns
        raise_form_error 'Unknown type of secret' if kind.nil?

        validate_recipient
        validate_share_domain
        validate_passphrase
      end

      def process
        create_secret_pair
        handle_success
      end

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump,
            secret: secret.safe_dump,
            share_domain: share_domain, # we return the value, but don't save it
          },
          details: {
            kind: kind,
            recipient: recipient,
            recipient_safe: recipient_safe,
          },
        }
      end

      def form_fields
        {
          share_domain: share_domain,
          secret: secret_value,
          recipient: recipient,
          ttl: ttl,
          kind: kind,
        }
      end

      def redirect_uri
        ['/receipt/', metadata.identifier].join
      end

      protected

      def process_ttl
        @ttl = payload.fetch('ttl', nil)

        # Get configuration options. We can rely on these values existing
        # because that are guaranteed by OT::Config.after_load.
        secret_options = OT.conf&.fetch('secret_options', {
          'default_ttl' => 7.days,
          'ttl_options' => [1.minute, 1.hour, 1.day, 7.days],
        }
        )
        default_ttl    = secret_options['default_ttl']
        ttl_options    = secret_options['ttl_options']

        # Get min/max values safely
        min_ttl = ttl_options.min || 1.minute # Fallback to 1 minute
        max_ttl = ttl_options.max || 30.days

        # Apply default if nil
        @ttl = default_ttl || 7.days if ttl.nil?

        # Convert to integer, now that we know it has a value
        @ttl = ttl.to_i

        # Apply a global maximum
        @ttl = 30.days if ttl && ttl >= 30.days

        # Enforce bounds
        @ttl = min_ttl if ttl < min_ttl
        @ttl = max_ttl if ttl > max_ttl
      end

      def process_secret
        raise NotImplementedError, 'You must implement process_secret'
      end

      def process_passphrase
        @passphrase = payload['passphrase'].to_s
      end

      def process_recipient
        payload['recipient'] = [payload['recipient']].flatten.compact.uniq # force a list
        r                    = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/
        @recipient           = payload['recipient'].collect do |email_address|
          next if email_address.to_s.empty?

          email_address.scan(r).uniq.first
        end.compact.uniq
        @recipient_safe      = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end

      # Capture the selected domain the link is meant for, as long as it's
      # a valid public domain (no pub intended). This is the same validation
      # that CustomDomain objects go through so if we don't get past this
      # most basic of checks, then whatever this is never had a whisker's
      # chance in a lion's den of being a custom domain anyway.
      def process_share_domain
        potential_domain = payload[:share_domain].to_s
        return if potential_domain.empty?

        unless Onetime::CustomDomain.valid?(potential_domain)
          secret_logger.info 'Invalid share domain', {
            domain: potential_domain,
            action: 'validate_share_domain',
            result: :invalid,
          }
          return
        end

        # If the given domain is the same as the site's host domain, then
        # we simply skip the share domain stuff altogether.
        if Onetime::CustomDomain.default_domain?(potential_domain)
          secret_logger.info 'Ignoring default share domain', {
            domain: potential_domain,
            action: 'validate_share_domain',
            result: :default_domain_skipped,
          }
          return
        end

        # Otherewise, it's good to go.
        @share_domain = potential_domain
      end

      def validate_recipient
        return if recipient.empty?

        raise_form_error 'An account is required to send emails.', field: 'recipient', error_type: 'requires_account' if cust.anonymous?
        recipient.each do |recip|
          raise_form_error "Undeliverable email address: #{recip}", field: 'recipient', error_type: 'invalid_email' unless valid_email?(recip)
        end
      end

      # Validates the share domain for secret creation.
      # Determines appropriate domain and validates access permissions.
      def validate_share_domain
        # If we're on a custom domain creating a link, the only possible share
        # domain  is the custom domain itself. This is bc we only allow logging
        # in on the canonical domain (e.g. onetimesecret.com) AND we don't offer
        # any way to change the share domain when creating a link from a custom
        # domain.
        @share_domain = determine_share_domain
        validate_domain_access(@share_domain)
      end

      def validate_passphrase
        # Get passphrase configuration
        passphrase_config = OT.conf.dig('site', 'secret_options', 'passphrase') || {}

        # Check if passphrase is required
        if passphrase_config['required'] && passphrase.to_s.empty?
          raise_form_error 'A passphrase is required for all secrets'
        end

        # Skip further validation if no passphrase provided
        return if passphrase.to_s.empty?

        # Validate minimum length
        min_length = passphrase_config['minimum_length'] || nil
        if min_length && passphrase.length < min_length
          raise_form_error "Passphrase must be at least #{min_length} characters long"
        end

        # Validate maximum length
        max_length = passphrase_config['maximum_length'] || nil
        if max_length && passphrase.length > max_length
          raise_form_error "Passphrase must be no more than #{max_length} characters long"
        end

        # Validate complexity if required
        if passphrase_config['enforce_complexity']
          validate_passphrase_complexity
        end
      end

      def validate_passphrase_complexity
        errors = []

        # Check for at least one uppercase letter
        errors << 'uppercase letter' unless passphrase.match?(/[A-Z]/)

        # Check for at least one lowercase letter
        errors << 'lowercase letter' unless passphrase.match?(/[a-z]/)

        # Check for at least one number
        errors << 'number' unless passphrase.match?(/\d/)

        # Check for at least one symbol
        errors << 'symbol' unless passphrase.match?(%r{[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?~`]})

        unless errors.empty?
          raise_form_error "Passphrase must contain at least one #{errors.join(', ')}"
        end
      end

      private

      def create_secret_pair
        # def spawn_pair(owner_id, lifespan, content, passphrase: nil, domain: nil)
        @metadata, @secret = Onetime::Metadata.spawn_pair(
          cust&.objid, ttl, secret_value, passphrase: passphrase, domain: share_domain
        )

        @greenlighted = metadata.valid? && secret.valid?
      end

      def handle_success
        return raise_form_error 'Could not store your secret' unless greenlighted

        update_stats
        send_email_to_recipient

        success_data
      end

      def update_stats
        unless cust.anonymous?
          cust.add_metadata metadata
          cust.increment_field :secrets_created
        end
        Onetime::Customer.secrets_created.increment
      end

      def send_email_to_recipient
        return if recipient.nil? || recipient.empty?

        klass = OT::Mail::SecretLink
        metadata.deliver_by_email cust, locale, secret, recipient.first, klass
      end

      # Determines which domain should be used for sharing.
      # Uses display domain if on custom domain, otherwise uses specified share domain.
      #
      # @return [String, nil] The domain to use for sharing
      def determine_share_domain
        return display_domain if custom_domain?

        share_domain
      end

      # Validates domain exists and checks access permissions.
      #
      # @param domain [String, nil] Domain to validate
      # @raise [FormError] If domain is invalid or access is not permitted
      def validate_domain_access(domain)
        return if domain.nil?

        # e.g. dbkey -> customdomain:display_domains -> hash -> key: value
        # where key is the domain and value is the domainid
        domain_record = Onetime::CustomDomain.from_display_domain(domain)
        raise_form_error "Unknown domain: #{domain}" if domain_record.nil?

        secret_logger.debug 'Validating domain access', {
          domain: domain,
          custom_domain: custom_domain?,
          allow_public: domain_record.allow_public_homepage?,
          is_owner: domain_record.owner?(@cust),
          user_id: @cust&.objid,
        }

        validate_domain_permissions(domain_record)
      end

      # Validates domain permissions based on context and configuration.
      #
      # @param domain_record [CustomDomain] The domain record to validate
      # @raise [FormError] If access is not permitted
      #
      # Validation Rules:
      # - On custom domains:
      #   - Allows access if public sharing is enabled
      #   - Rejects if public sharing is disabled
      # - On canonical domain:
      #   - Requires domain ownership
      def validate_domain_permissions(domain_record)
        if custom_domain?
          return if domain_record.allow_public_homepage?

          secret_logger.warn 'Public sharing disabled for domain', {
            domain: share_domain,
            user_id: @cust&.objid,
            action: 'validate_domain_permissions',
            result: :access_denied,
          }
          raise_form_error "Public sharing disabled for domain: #{share_domain}"
        end

        return if domain_record.owner?(@cust)

        secret_logger.info 'Non-owner attempted domain access', {
          domain: share_domain,
          user_id: cust.objid,
          action: 'validate_domain_permissions',
          result: :non_owner,
        }
      end
    end
  end
end
