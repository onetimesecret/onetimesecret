# apps/api/incoming/logic/create_incoming_secret.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../../../../lib/onetime/jobs/publisher'
require_relative '../../../../lib/onetime/incoming/recipient_resolver'

module Incoming
  module Logic
    # Creates a secret from an incoming request and notifies the recipient.
    #
    # Domain-aware: uses RecipientResolver to look up recipients from
    # either global config (canonical) or per-domain config (custom).
    #
    # @example Request
    #   POST /api/incoming/secret
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
    #     record: { receipt: {...}, secret: {...} },
    #     details: { memo: "...", recipient: "abc123..." }
    #   }
    #
    # @api Create a secret destined for a pre-configured recipient and
    #   send them an email notification. The recipient is identified by
    #   a hash rather than a raw email address. Returns the receipt and
    #   secret metadata on success.
    class CreateIncomingSecret < Incoming::Logic::Base
      include Onetime::LoggerMethods

      SCHEMAS = { response: 'incomingSecret' }.freeze

      attr_reader :memo, :secret_value, :recipient_email, :recipient_hash, :ttl, :passphrase, :receipt, :secret, :greenlighted

      def process_params
        # All parameters are passed in the :secret hash like other V3 endpoints
        @payload = params['secret'] || {}
        raise_form_error 'Incorrect payload format' if @payload.is_a?(String)

        # Extract memo with safe default max length (domain config applied later)
        @memo = sanitize_plain_text(@payload['memo'].to_s, max_length: 500)

        # Extract secret value
        @secret_value = @payload['secret'].to_s

        # Extract recipient hash instead of email
        @recipient_hash = sanitize_identifier(@payload['recipient'].to_s.strip)

        # Set passphrase from global config (not per-domain yet)
        incoming_config = OT.conf.dig('features', 'incoming') || {}
        @passphrase     = incoming_config['default_passphrase']

        # NOTE: Resolver calls (config_data, lookup) are deferred to
        # raise_concerns/process to avoid Redis I/O before entitlement check
      end

      def raise_concerns
        # On custom domains, require the domain-owning org's entitlement.
        # Uses the resolver to check the org that owns the domain, not
        # the session org (which is nil for anonymous visitors).
        resolver.require_domain_entitlement!('incoming_secrets')

        # Check if feature is enabled (domain-aware)
        unless resolver.enabled?
          raise_form_error 'Incoming secrets feature is not enabled'
        end

        # Validate required fields (memo is optional)
        raise_form_error 'Secret content is required' if secret_value.empty?
        raise_form_error 'Recipient is required' if @recipient_hash.to_s.empty?

        # Now safe to perform resolver I/O (entitlement verified)
        resolve_recipient_and_config

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

        # Validate that spawn_pair produced valid objects before recording
        # stats or enqueuing notifications for a potentially invalid secret.
        @greenlighted = receipt.valid? && secret.valid?
        raise_form_error 'Failed to create secret' unless @greenlighted

        # Update stats
        update_customer_stats

        # Send notification email
        send_recipient_notification

        success_data
      end

      def success_data
        {
          success: greenlighted,
          record: {
            receipt: receipt.safe_dump,
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

      def resolver
        @resolver ||= Onetime::Incoming::RecipientResolver.new(
          domain_strategy: domain_strategy,
          display_domain: display_domain,
        )
      end

      # Performs resolver I/O after entitlement check passes.
      # Sets @recipient_email, @ttl, and re-truncates @memo per domain config.
      def resolve_recipient_and_config
        domain_config = resolver.config_data

        # Look up actual email from hash via domain-aware resolver
        @recipient_email = resolver.lookup(@recipient_hash)

        Onetime.secret_logger.debug "[IncomingSecret] Recipient hash: #{@recipient_hash} -> #{@recipient_email ? OT::Utils.obscure_email(@recipient_email) : 'not found'}"

        # Apply domain-aware memo max length (re-truncate if needed)
        memo_max = domain_config[:memo_max_length] || 50
        @memo    = @memo.slice(0, memo_max) if @memo.length > memo_max

        # Set TTL from domain-aware config
        @ttl = domain_config[:default_ttl] || 604_800 # 7 days fallback
      end

      def create_and_encrypt_secret
        # Use Receipt.spawn_pair to create linked secret and receipt
        @receipt, @secret = Onetime::Receipt.spawn_pair(
          cust&.objid || 'anon',
          ttl,
          secret_value,
          passphrase: passphrase,
        )

        # Store incoming-specific fields
        receipt.memo       = memo
        receipt.recipients = recipient_email
        receipt.save
      end

      def update_customer_stats
        # Update customer stats if not anonymous
        unless anonymous_user?
          cust.add_receipt receipt
          cust.increment_field :secrets_created
        end

        # Update global stats
        Onetime::Customer.secrets_created.increment
      end

      def send_recipient_notification
        return if recipient_email.nil? || recipient_email.empty?

        # Resolve share_domain to domain_id for sender config (nil-safe)
        domain_id = Onetime::CustomDomain.resolve_domain_id(secret.share_domain)

        Onetime::Jobs::Publisher.enqueue_email(
          :incoming_secret,
          {
            secret_key: secret.identifier,
            share_domain: secret.share_domain,
            recipient: recipient_email,
            memo: memo,
            has_passphrase: !passphrase.to_s.empty?,
            locale: locale || OT.default_locale,
          },
          domain_id: domain_id,
        )

        Onetime.secret_logger.info "[IncomingSecret] Notification enqueued for #{OT::Utils.obscure_email(recipient_email)} (receipt: #{receipt.shortid})"
      rescue StandardError => ex
        Onetime.secret_logger.error "[IncomingSecret] Failed to enqueue notification: #{ex.message}"
        # Don't raise - email failure shouldn't prevent secret creation
      end
    end
  end
end
