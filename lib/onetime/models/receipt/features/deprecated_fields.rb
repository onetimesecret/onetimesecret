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
        # Resolve share_domain FQDN to a domain_id for sender config lookup.
        # Fault-tolerant: any failure results in nil (system default sender).
        domain_id     = Onetime::CustomDomain.resolve_domain_id(secret.share_domain)

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
            has_passphrase: secret.has_passphrase?,
            locale: locale || OT.default_locale,
          },
          domain_id: domain_id,
        ) # fallback: :async_thread is the default
      end

      # NOTE: We override the default fast writer (bang!) methods from familia
      # so that we can update two fields at once. To replicate the same behavior
      # we pass update_expiration: false to save so that changing this receipt
      # object's state doesn't affect its original expiration time.
      #
      # Every transition is gated by an atomic compare-and-set on the persisted
      # +state+ field ({#compare_and_set_state!}) so it FAILS CLOSED. If the
      # receipt's Redis key was TTL-evicted between the time this instance was
      # loaded and the time the transition runs, the CAS's HGET matches nothing,
      # the claim loses, and the unconditional `save` never fires -- so an
      # evicted receipt is not resurrected as a TTL-less "immortal" key (#3625).
      # If a concurrent caller already advanced the state, the CAS also loses, so
      # a stale instance can never revert an already-terminal receipt. Only the
      # caller that wins the claim persists the accompanying fields and emits the
      # log/audit side effects.
      #
      # The winner's follow-up field writes still go through
      # `save update_expiration: false` so advancing state never resets the
      # receipt's original expiration. That write lands on the key the CAS just
      # confirmed exists, so an HSET/HMSET on a live key leaves its TTL untouched
      # -- exactly the guarantee `update_expiration: false` was approximating.
      #
      # TODO: Replace with transaction (i.e. MULTI/EXEC command)

      # MIGRATION NOTE: Replaces legacy `received!` method.
      # - Sets state to 'revealed' (was 'received')
      # - Sets `revealed` timestamp (legacy `received` kept for backward compat in safe_dump)
      # - Clears secret_identifier
      #
      # @param actor_context [Hash, nil] request-scoped audit context (e.g. the
      #   actor discriminator) threaded down from the reveal cascade (#3639).
      #   Forwarded to the org audit trail; nil is treated as an unknown/anonymous
      #   actor (never misattributed to the creator). See #lifecycle_audit_attrs.
      # @return [Boolean, nil] true if THIS caller performed the transition;
      #   a falsy value if the in-memory guard or the atomic claim lost.
      def revealed!(actor_context: nil)
        # In-memory fast-path: short-circuit an already-terminal instance before
        # touching Redis. The authoritative, resurrection-proof guard is the CAS.
        return unless state?(:new) || state?(:previewed)
        return unless compare_and_set_state!(:revealed, [:new, :previewed])

        previous_state         = state
        original_secret_id     = secret_identifier
        self.state             = 'revealed'
        self.revealed          = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to revealed',
          {
            receipt_id: shortid,
            secret_id: original_secret_id,
            previous_state: previous_state,
            new_state: 'revealed',
            timestamp: revealed,
          }

        # The audit event fires only inside the won-CAS branch, so the actor is
        # recorded exactly once; a race loser returned above and records nothing.
        record_org_audit_event('revealed', **lifecycle_audit_attrs(actor_context))
        true
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
        return unless compare_and_set_state!(:orphaned, [:new, :previewed])

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

        record_org_audit_event('orphaned')
        true
      end

      # @param actor_context [Hash, nil] request-scoped audit context threaded
      #   down from the burn cascade (#3639); see #revealed! and
      #   #lifecycle_audit_attrs. nil is treated as an unknown/anonymous actor.
      def burned!(actor_context: nil)
        # See guard comment on `revealed!` (was `received!`)
        return unless state?(:new) || state?(:previewed)
        return unless compare_and_set_state!(:burned, [:new, :previewed])

        previous_state         = state
        original_secret_id     = secret_identifier
        self.state             = 'burned'
        self.burned            = Familia.now.to_i
        self.secret_identifier = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to burned',
          {
            receipt_id: shortid,
            secret_id: original_secret_id,
            previous_state: previous_state,
            new_state: 'burned',
            timestamp: burned,
          }

        # Actor recorded exactly once inside the won-CAS branch (see revealed!).
        record_org_audit_event('burned', **lifecycle_audit_attrs(actor_context))
        true
      end

      def expired!
        # A guard to prevent prematurely expiring a secret. We only want to
        # expire secrets that are actually old enough to be expired.
        return unless secret_expired?

        # Only a live receipt can expire. Unlike the sibling transitions this
        # method had no state guard, and secret_expired? stays true forever --
        # so every later view of an expired receipt re-ran the transition
        # (redundant save, duplicate logs, duplicate audit events).
        return unless state?(:new) || state?(:previewed)
        return unless compare_and_set_state!(:expired, [:new, :previewed])

        previous_state         = state
        original_secret_id     = secret_identifier
        self.state             = 'expired'
        self.updated           = Familia.now.to_i
        self.secret_identifier = ''
        self.secret_key        = ''
        save update_expiration: false

        secret_logger.info 'Receipt state transition to expired',
          {
            receipt_id: shortid,
            secret_id: original_secret_id,
            previous_state: previous_state,
            new_state: 'expired',
            timestamp: updated,
            secret_ttl: secret_ttl,
            age_seconds: age,
          }

        record_org_audit_event('expired')
        true
      end

      def state?(guess)
        state.to_s == guess.to_s
      end

      # Backward compatibility aliases for legacy method names
      alias received! revealed!

      def truncated?
        truncate.to_s == 'true'
      end

      private

      # Normalize the request-scoped actor context threaded into a lifecycle
      # transition (revealed!/burned!, #3639) into string-keyed audit attributes.
      #
      # The org audit trail records the terminal lifecycle events with WHO acted
      # ('actor' => 'creator' | 'authenticated_other' | 'anonymous'), computed at
      # the logic layer where the request's customer is in scope. This model
      # method never sees request context, so it fails safe: a missing/blank
      # actor context is recorded as 'anonymous' — the same "never misattribute an
      # unknown actor to the creator" precedent the fetch-side telemetry follows.
      # Callers without request context (v1 paths, account verification, direct
      # receipt.revealed! test calls) therefore still emit a well-formed actor.
      #
      # Recognized actor discriminators. An empty or unexpected value fails
      # safe to 'anonymous' rather than being recorded verbatim: the trail must
      # never carry an actor label the rest of the system doesn't understand,
      # and an unknown actor must never be misattributed to the creator.
      LIFECYCLE_ACTORS = %w[creator authenticated_other anonymous].freeze

      # Max length of a stored actor_id, matching Receipt#shortid
      # (objid.slice(0, 8)). Clamping here is defense in depth so a full
      # objid/custid can never leak into the trail even if a caller supplies an
      # unreduced value.
      ACTOR_ID_MAX_LENGTH = 8

      # @param actor_context [Hash, nil] string- or symbol-keyed audit attrs.
      # @return [Hash] string-keyed attrs with a guaranteed known 'actor' and,
      #   for authenticated actors only, an 8-char 'actor_id'.
      def lifecycle_audit_attrs(actor_context)
        attrs = actor_context.is_a?(Hash) ? actor_context.transform_keys(&:to_s) : {}

        # Fail safe: an empty or unrecognized actor becomes 'anonymous'.
        actor          = attrs['actor'].to_s
        actor          = 'anonymous' unless LIFECYCLE_ACTORS.include?(actor)
        attrs['actor'] = actor

        if actor == 'anonymous'
          # An anonymous event has no identity: never attach an id to it, even
          # if a caller supplied one.
          attrs.delete('actor_id')
        elsif attrs.key?('actor_id')
          # Authenticated actor: keep the id but clamp it to the shortid policy;
          # drop it entirely if blank so we never store an empty token.
          id = attrs['actor_id'].to_s
          if id.empty?
            attrs.delete('actor_id')
          else
            attrs['actor_id'] = id.slice(0, ACTOR_ID_MAX_LENGTH)
          end
        end

        attrs
      end

      # See Onetime::Models::Features::StateCas for +compare_and_set_state!+,
      # the shared atomic guard each transition above claims through.
    end
  end
end
