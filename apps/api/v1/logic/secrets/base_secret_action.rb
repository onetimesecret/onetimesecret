# lib/onetime/logic/secrets/base_secret_action.rb

module V1::Logic
  module Secrets
    class BaseSecretAction < V1::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :greenlighted
      attr_reader :metadata, :secret, :share_domain, :custom_domain, :payload
      attr_accessor :token
      using Onetime::RackRefinements

      # Process methods populate instance variables with the values. The
      # raise_concerns and process methods deal with the values in the instance
      # variables only (no more params access).
      def process_params
        # All parameters are passed in the :secret hash (secret[:ttl], etc)
        @payload = params[:secret] || {}
        raise_form_error "Incorrect payload format" if payload.is_a?(String)
        process_ttl
        process_secret
        process_passphrase
        process_recipient
        process_share_domain
      end

      def raise_concerns
        limit_action :create_secret
        limit_action :email_recipient unless recipient.empty?
        raise_form_error "Unknown type of secret" if kind.nil?
        validate_recipient
        validate_share_domain
      end

      def process
        create_secret_pair
        handle_passphrase
        save_secret
        handle_success
      end

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump,
            secret: secret.safe_dump,
            share_domain: share_domain
          },
          details: {
            kind: kind,
            recipient: recipient,
            recipient_safe: recipient_safe
          }
        }
      end

      def form_fields
        {
          share_domain: share_domain,
          secret: secret_value,
          recipient: recipient,
          ttl: ttl,
          kind: kind
        }
      end

      def redirect_uri
        ['/private/', metadata.key].join
      end

      protected

      def process_ttl
        @ttl = payload.fetch(:ttl, nil)

        # Get configuration options. We can rely on these values existing
        # because that are guaranteed by OT::Config.after_load.
        secret_options = OT.conf[:site][:secret_options]
        default_ttl = secret_options[:default_ttl]
        ttl_options = secret_options[:ttl_options]

        # Get min/max values safely
        min_ttl = ttl_options.min || 1.minute      # Fallback to 1 minute
        max_ttl = plan.options[:ttl] || ttl_options.max || 7.days  # Fallback to 7 days

        # Apply default if nil
        @ttl = default_ttl || 7.days if ttl.nil?

        # Convert to integer
        @ttl = ttl.to_i

        # Apply plan constraints
        @ttl = plan.options[:ttl] if ttl && ttl >= plan.options[:ttl]

        # Enforce bounds
        @ttl = min_ttl if ttl < min_ttl
        @ttl = max_ttl if ttl > max_ttl
      end

      def process_secret
        raise NotImplementedError, "You must implement process_secret"
      end

      def process_passphrase
        @passphrase = payload[:passphrase].to_s
      end

      def process_recipient
        payload[:recipient] = [payload[:recipient]].flatten.compact.uniq # force a list
        r = Regexp.new(/\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/)
        @recipient = payload[:recipient].collect { |email_address|
          next if email_address.to_s.empty?
          email_address.scan(r).uniq.first
        }.compact.uniq
        @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end

      # Capture the selected domain the link is meant for, as long as it's
      # a valid public domain (no pub intended). This is the same validation
      # that CustomDomain objects go through so if we don't get past this
      # most basic of checks, then whatever this is never had a whisker's
      # chance in a lion's den of being a custom domain anyway.
      def process_share_domain

        potential_domain = payload[:share_domain].to_s
        return if potential_domain.empty?

        unless OT::CustomDomain.valid?(potential_domain)
          return OT.info "[BaseSecretAction] Invalid share domain #{potential_domain}"
        end

        # If the given domain is the same as the site's host domain, then
        # we simply skip the share domain stuff altogether.
        if OT::CustomDomain.default_domain?(potential_domain)
          return OT.info "[BaseSecretAction] Ignoring default share domain: #{potential_domain}"
        end

        # Otherewise, it's good to go.
        @share_domain = potential_domain
      end

      def validate_recipient
        return if recipient.empty?
        raise_form_error "An account is required to send emails." if cust.anonymous?
        recipient.each do |recip|
          raise_form_error "Undeliverable email address: #{recip}" unless valid_email?(recip)
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

      private

      def create_secret_pair
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, token
      end

      def handle_passphrase
        return if passphrase.to_s.empty?
        secret.update_passphrase passphrase
        metadata.passphrase = secret.passphrase
      end

      def save_secret
        secret.encrypt_value secret_value, :size => plan.options[:size]
        metadata.ttl, secret.ttl = ttl*2, ttl
        metadata.lifespan = metadata.ttl.to_i
        metadata.secret_ttl = secret.ttl.to_i
        metadata.secret_shortkey = secret.shortkey
        metadata.share_domain = share_domain
        secret.lifespan = secret.ttl.to_i
        secret.share_domain = share_domain
        secret.save
        metadata.save
        @greenlighted = metadata.valid? && secret.valid?
      end

      def handle_success
        return raise_form_error "Could not store your secret" unless greenlighted
        update_stats
        send_email_notification
      end

      def update_stats
        unless cust.anonymous?
          cust.add_metadata metadata
          cust.increment_field :secrets_created
        end
        V1::Customer.global.increment_field :secrets_created
        V1::Logic.stathat_count("Secrets", 1)
      end

      def send_email_notification
        return if recipient.nil? || recipient.empty?
        klass = OT::App::Mail::SecretLink
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

        # e.g. rediskey -> customdomain:display_domains -> hash -> key: value
        # where key is the domain and value is the domainid
        domain_record = OT::CustomDomain.from_display_domain(domain)
        raise_form_error "Unknown domain: #{domain}" if domain_record.nil?

        OT.ld <<~DEBUG
          [BaseSecretAction]
            class:     #{self.class}
            share_domain:   #{@share_domain}
            custom_domain?:  #{custom_domain?}
            allow_public?:   #{domain_record.allow_public_homepage?}
            owner?:          #{domain_record.owner?(@cust)}
        DEBUG

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
          raise_form_error "Public sharing disabled for domain: #{share_domain}"
        end

        unless domain_record.owner?(@cust)
          OT.li "[validate_domain_perm]: #{share_domain} non-owner [#{cust.custid}]"
        end
      end
    end
  end
end
