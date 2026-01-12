# apps/api/v3/logic/incoming/create_incoming_secret.rb
#
# frozen_string_literal: true

require_relative '../base'

module V3
  module Logic
    module Incoming
      # Creates a secret from an incoming request and notifies the recipient.
      #
      # This is used by anonymous users to send secrets to pre-configured
      # recipients. The recipient receives an email notification.
      #
      # @example Request
      #   POST /api/v3/incoming/secret
      #   {
      #     secret: {
      #       memo: "Password reset request",
      #       secret: "the-sensitive-content",
      #       recipient: "abc123..."  # Hash of recipient email
      #     }
      #   }
      #
      # @example Response
      #   {
      #     success: true,
      #     record: { metadata: {...}, secret: {...} },
      #     details: { memo: "...", recipient: "abc123..." }
      #   }
      #
      class CreateIncomingSecret < V3::Logic::Base
        include Onetime::LoggerMethods

        attr_reader :memo, :secret_value, :recipient_email, :recipient_hash, :ttl, :passphrase, :metadata, :secret, :greenlighted

        def process_params
          # All parameters are passed in the :secret hash like other V3 endpoints
          @payload = params['secret'] || {}
          raise_form_error 'Incorrect payload format' if @payload.is_a?(String)

          incoming_config = OT.conf.dig('features', 'incoming') || {}

          # Extract and validate memo
          memo_max = incoming_config['memo_max_length'] || 50
          @memo    = sanitize_plain_text(@payload['memo'].to_s, max_length: memo_max)

          # Extract secret value
          @secret_value = @payload['secret'].to_s

          # Extract recipient hash instead of email
          @recipient_hash = sanitize_identifier(@payload['recipient'].to_s.strip)

          # Look up actual email from hash
          @recipient_email = OT.lookup_incoming_recipient(@recipient_hash)

          Onetime.secret_logger.debug "[IncomingSecret] Recipient hash: #{@recipient_hash} -> #{@recipient_email ? OT::Utils.obscure_email(@recipient_email) : 'not found'}"

          # Set TTL from config or use default
          @ttl = incoming_config['default_ttl'] || 604_800 # 7 days

          # Set passphrase from config (can be nil)
          @passphrase = incoming_config['default_passphrase']
        end

        def raise_concerns
          # Check if feature is enabled
          incoming_config = OT.conf.dig('features', 'incoming') || {}
          unless incoming_config['enabled']
            raise_form_error 'Incoming secrets feature is not enabled'
          end

          # Validate required fields (memo is optional)
          raise_form_error 'Secret content is required' if secret_value.empty?
          raise_form_error 'Recipient is required' if @recipient_hash.to_s.empty?

          # Validate recipient hash exists and maps to valid email
          if @recipient_email.nil?
            OT.lw "[IncomingSecret] Invalid recipient hash attempted: #{@recipient_hash}"
            raise_form_error 'Invalid recipient'
          end

          unless recipient_email.to_s.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
            OT.le "[IncomingSecret] Lookup returned invalid email for hash: #{@recipient_hash}"
            raise_form_error 'Invalid recipient configuration'
          end
        end

        def process
          # Create and encrypt secret
          create_and_encrypt_secret

          # Update stats
          update_customer_stats

          # Send notification email
          send_recipient_notification

          @greenlighted = metadata.valid? && secret.valid?

          success_data
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
              recipient: recipient_hash, # Return hash, not email
            },
          }
        end

        def form_fields
          {
            memo: memo,
            secret: secret_value,
            recipient: recipient_hash, # Return hash, not email
          }
        end

        private

        def create_and_encrypt_secret
          # Use Receipt.spawn_pair to create linked secret and receipt
          @metadata, @secret = Onetime::Receipt.spawn_pair(
            cust&.objid || 'anon',
            ttl,
            secret_value,
            passphrase: passphrase,
          )

          # Store incoming-specific fields
          metadata.memo       = memo
          metadata.recipients = recipient_email
          metadata.save
        end

        def update_customer_stats
          # Update customer stats if not anonymous
          unless cust.anonymous?
            cust.add_receipt metadata
            cust.increment_field :secrets_created
          end

          # Update global stats
          Onetime::Customer.secrets_created.increment
        end

        def send_recipient_notification
          return if recipient_email.nil? || recipient_email.empty?

          # NOTE: Email notification for incoming secrets is not yet implemented
          # in this branch. The IncomingSecretNotification mail view class needs
          # to be created, along with the corresponding HTML template.
          #
          # The implementation should:
          # 1. Create OT::Mail::IncomingSecretNotification class
          # 2. Create templates/mail/incoming_secret_notification.html template
          # 3. Call metadata.deliver_by_email with the appropriate parameters
          #
          # Example of intended implementation:
          #   klass = OT::Mail::IncomingSecretNotification
          #   metadata.deliver_by_email(cust, locale, secret, recipient_email, klass)
          #
          # For now, we log the event but don't send the email.

          Onetime.secret_logger.info "[IncomingSecret] Secret created for #{OT::Utils.obscure_email(recipient_email)} (metadata: #{metadata.shortid})"
          Onetime.secret_logger.warn '[IncomingSecret] Email notification not sent - IncomingSecretNotification mail class not implemented'
        rescue StandardError => ex
          Onetime.secret_logger.error "[IncomingSecret] Failed to send email notification: #{ex.message}"
          # Don't raise - email failure shouldn't prevent secret creation
        end
      end
    end
  end
end
