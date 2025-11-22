# apps/api/v2/logic/incoming/create_incoming_secret.rb

require_relative '../base'

module V2::Logic
  module Incoming
    class CreateIncomingSecret < V2::Logic::Base
      attr_reader :memo, :secret_value, :recipient_email, :recipient_hash, :ttl, :passphrase
      attr_reader :metadata, :secret, :greenlighted

      def process_params
        # All parameters are passed in the :secret hash like other V2 endpoints
        @payload = params[:secret] || {}
        raise_form_error "Incorrect payload format" if @payload.is_a?(String)

        incoming_config = OT.conf.dig(:features, :incoming) || {}

        # Extract and validate memo
        memo_max = incoming_config[:memo_max_length] || 50
        @memo = @payload[:memo].to_s.strip[0...memo_max]

        # Extract secret value
        @secret_value = @payload[:secret].to_s

        # Extract recipient hash instead of email
        @recipient_hash = @payload[:recipient].to_s.strip

        # Look up actual email from hash
        @recipient_email = OT.lookup_incoming_recipient(@recipient_hash)

        OT.debug "[IncomingSecret] Recipient hash: #{@recipient_hash} -> #{@recipient_email ? OT::Utils.obscure_email(@recipient_email) : 'not found'}"

        # Set TTL from config or use default
        @ttl = incoming_config[:default_ttl] || 604800 # 7 days

        # Set passphrase from config (can be nil)
        @passphrase = incoming_config[:default_passphrase]
      end

      def raise_concerns
        # Check if feature is enabled
        incoming_config = OT.conf.dig(:features, :incoming) || {}
        unless incoming_config[:enabled]
          raise_form_error "Incoming secrets feature is not enabled"
        end

        # Validate required fields (memo is optional)
        raise_form_error "Secret content is required" if secret_value.empty?
        raise_form_error "Recipient is required" if @recipient_hash.to_s.empty?

        # Validate recipient hash exists and maps to valid email
        if @recipient_email.nil?
          OT.warn "[IncomingSecret] Invalid recipient hash attempted: #{@recipient_hash}"
          raise_form_error "Invalid recipient"
        end

        unless recipient_email.to_s.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          OT.error "[IncomingSecret] Lookup returned invalid email for hash: #{@recipient_hash}"
          raise_form_error "Invalid recipient configuration"
        end

        # Apply rate limits
        limit_action :create_secret
        limit_action :email_recipient
      end

      def process
        # Create and encrypt secret using V2 pattern
        create_and_encrypt_secret

        # Update stats
        update_customer_stats

        # Send notification email
        send_recipient_notification

        @greenlighted = metadata.valid? && secret.valid?
      end

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump,
            secret: secret.safe_dump,
          },
          details: {
            memo: memo,
            recipient: recipient_hash,  # Return hash, not email
          },
        }
      end

      def form_fields
        {
          memo: memo,
          secret: secret_value,
          recipient: recipient_hash,  # Return hash, not email
        }
      end

      private

      def create_and_encrypt_secret
        # Use V2::Secret.spawn_pair to create linked secret and metadata
        @metadata, @secret = V2::Secret.spawn_pair cust.custid, nil

        # Store incoming-specific fields
        metadata.memo = memo
        metadata.recipients = recipient_email

        # Apply passphrase if configured
        unless passphrase.to_s.empty?
          secret.update_passphrase passphrase
          metadata.passphrase = secret.passphrase
        end

        # Encrypt the secret value
        secret.encrypt_value secret_value, size: plan.options[:size]

        # Set TTLs
        metadata.ttl = ttl * 2
        secret.ttl = ttl
        metadata.lifespan = metadata.ttl.to_i
        metadata.secret_ttl = secret.ttl.to_i
        secret.lifespan = secret.ttl.to_i

        # Store shortkey in metadata
        metadata.secret_shortkey = secret.shortkey

        # Save both
        secret.save
        metadata.save
      end

      def update_customer_stats
        # Update customer stats if not anonymous
        unless cust.anonymous?
          cust.add_metadata metadata
          cust.increment_field :secrets_created
        end

        # Update global stats
        V2::Customer.global.increment_field :secrets_created
        V2::Logic.stathat_count("Secrets", 1)
      end

      def send_recipient_notification
        return if recipient_email.nil? || recipient_email.empty?

        # Use a specialized template for incoming secrets
        klass = OT::Mail::IncomingSecretNotification

        # Create an anonymous customer object for the sender
        # This is needed for the deliver_by_email method signature
        anon_cust = V2::Customer.new(custid: 'anon')

        # Send the email using the existing delivery mechanism
        # Pass memo as additional parameter
        metadata.deliver_by_email(anon_cust, locale, secret, recipient_email, klass)

        OT.info "[IncomingSecret] Email notification sent to #{OT::Utils.obscure_email(recipient_email)} for secret #{secret.key}"
      rescue => e
        OT.error "[IncomingSecret] Failed to send email notification: #{e.message}"
        # Don't raise - email failure shouldn't prevent secret creation
      end
    end
  end
end
