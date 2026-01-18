# lib/onetime/models/receipt/features/deprecated_fields.rb
#
# frozen_string_literal: true

require_relative '../../../jobs/publisher'

module Onetime::Receipt::Features
  module DeprecatedFields
    Familia::Base.add_feature self, :deprecated_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field_group :deprecated_fields do
        base.field :key
        # MIGRATION NOTE: Legacy timestamp fields - kept for backward compatibility.
        # New code should use `previewed` and `revealed` instead.
        base.field :viewed, fast_method: false
        base.field :received, fast_method: false
        base.field :shared, fast_method: false
        base.field :burned, fast_method: false
        base.field :custid
        base.field :truncate # boolean
        base.field :secret_key # use secret_identifier
      end

      # MIGRATION NOTE: New canonical fields for state terminology rename.
      # - `previewed` replaces legacy `viewed` timestamp
      # - `revealed` replaces legacy `received` timestamp
      base.field :previewed, fast_method: false
      base.field :revealed, fast_method: false
    end

    module ClassMethods
    end

    module InstanceMethods
      def deliver_by_email(cust, locale, secret, eaddrs, _template = nil, _ticketno = nil)
        if eaddrs.nil? || eaddrs.empty?
          secret_logger.info 'No email addresses specified for delivery',
            {
              receipt_id: identifier,
              secret_id: secret.identifier,
              user: cust.obscure_email,
              action: 'deliver_email',
            }
          return
        end

        secret_logger.debug 'Preparing email delivery',
          {
            receipt_id: identifier,
            secret_id: secret.identifier,
            user: cust.obscure_email,
            action: 'deliver_email',
          }

        eaddrs = [eaddrs].flatten.compact[0..9] # Max 10

        eaddrs_safe     = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
        eaddrs_safe_str = eaddrs_safe.join(', ')

        secret_logger.info 'Delivering secret by email',
          {
            receipt_id: identifier,
            secret_id: secret.identifier,
            user: cust.obscure_email,
            recipient_count: eaddrs_safe.size,
            recipients: eaddrs_safe_str,
            action: 'deliver_email',
          }
        recipients! eaddrs_safe_str

        if eaddrs.size > 1
          secret_logger.warn 'Multiple recipients detected',
            {
              receipt_id: identifier,
              secret_id: secret.identifier,
              recipient_count: eaddrs.size,
              action: 'deliver_email',
            }
        end

        # Deliver to first recipient only
        email_address = eaddrs.first
        # Secret sharing: use default async_thread fallback (non-blocking)
        # User expects email but doesn't need to wait for it
        #
        # NOTE: Pass serializable data, not objects. The Secret object can't
        # be serialized to JSON for the message queue - it becomes "#<Secret:0x...>".
        # The template uses secret_key for the URL and share_domain for custom domains.
        # Use secret.identifier (not deprecated secret.key which may be nil)
        Onetime::Jobs::Publisher.enqueue_email(
          :secret_link,
          {
            secret_key: secret.identifier,
            share_domain: secret.share_domain,
            recipient: email_address,
            sender_email: cust.email,
            locale: locale || OT.default_locale,
          },
        ) # fallback: :async_thread is the default
      end

      # NOTE: We override the default fast writer (bang!) methods from familia
      # so that we can update two fields at once. To replicate the same behavior
      # we pass update_expiration: false to save so that changing this receipt
      # object's state doesn't affect its original expiration time.
      #
      # TODO: Replace with transaction (i.e. MULTI/EXEC command)

      # MIGRATION NOTE: Replaces legacy `viewed!` method.
      # - Sets state to 'previewed' (was 'viewed')
      # - Sets `previewed` timestamp (legacy `viewed` kept for backward compat in safe_dump)
      def previewed!
        # A guard to allow only a fresh, new secret to be previewed. Also ensures
        # that we don't support going from previewed back to something else.
        return unless state?(:new)

        self.state     = 'previewed'
        self.previewed = Familia.now.to_i
        # The nuance between being "previewed" vs "revealed" or "burned" is
        # that the secret link page has been requested (via GET)
        # but the "View Secret" button hasn't been clicked yet (i.e. we haven't
        # yet received the POST request that actually reveals the contents
        # of the secret). It's a subtle but important distinction bc it
        # communicates an amount of activity around the secret.
        save update_expiration: false

        secret_logger.info 'Receipt state transition to previewed',
          {
            receipt_id: shortid,
            secret_id: secret_identifier,
            previous_state: 'new',
            new_state: 'previewed',
            timestamp: previewed,
          }
      end

      # MIGRATION NOTE: Replaces legacy `received!` method.
      # - Sets state to 'revealed' (was 'received')
      # - Sets `revealed` timestamp (legacy `received` kept for backward compat in safe_dump)
      # - Clears secret_identifier
      def revealed!
        # A guard to allow only a fresh secret to be revealed. Also ensures
        # that we don't support going from revealed back to something else.
        return unless state?(:new) || state?(:previewed)

        previous_state         = state
        self.state             = 'revealed'
        self.revealed          = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to revealed',
          {
            receipt_id: shortid,
            secret_id: secret_identifier,
            previous_state: previous_state,
            new_state: 'revealed',
            timestamp: revealed,
          }
      end

      # We use this method in special cases where a receipt record exists with
      # a secret_id value but no valid secret object exists. This can happen
      # when a secret is manually deleted but the receipt record is not. Otherwise
      # it's a bug and although unintentional we want to handle it gracefully here.
      def orphaned!
        # A guard to prevent modifying receipt records that already have
        # cleared out the secret (and that probably have already set a reason).
        return if secret_identifier.to_s.empty?
        # Only new or previewed secrets can be orphaned (was state?(:viewed))
        return unless state?(:new) || state?(:previewed)

        previous_state         = state
        original_secret_id     = secret_identifier
        self.state             = 'orphaned'
        self.updated           = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.warn 'Receipt state transition to orphaned',
          {
            receipt_id: shortid,
            secret_id: original_secret_id,
            previous_state: previous_state,
            new_state: 'orphaned',
            timestamp: updated,
          }
      end

      def burned!
        # See guard comment on `revealed!` (was `received!`)
        return unless state?(:new) || state?(:previewed)

        previous_state         = state
        self.state             = 'burned'
        self.burned            = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to burned',
          {
            receipt_id: shortid,
            secret_id: secret_identifier,
            previous_state: previous_state,
            new_state: 'burned',
            timestamp: burned,
          }
      end

      def expired!
        # A guard to prevent prematurely expiring a secret. We only want to
        # expire secrets that are actually old enough to be expired.
        return unless secret_expired?

        previous_state         = state
        self.state             = 'expired'
        self.updated           = Familia.now.to_i
        self.secret_identifier = ''
        self.secret_key        = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to expired',
          {
            receipt_id: shortid,
            secret_id: secret_identifier,
            previous_state: previous_state,
            new_state: 'expired',
            timestamp: updated,
            secret_ttl: secret_ttl,
            age_seconds: age,
          }
      end

      def state?(guess)
        state.to_s == guess.to_s
      end

      def truncated?
        truncate.to_s == 'true'
      end
    end
  end
end
