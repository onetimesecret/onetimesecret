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
        # secret_key (the pre-v0.24 name of secret_identifier) is no longer
        # declared. Familia reads and writes declared fields only: a load
        # assigns them, and save HMSETs their values and HDELs the ones set
        # to nil, touching nothing else in the hash. So a stale secret_key on
        # a receipt written before the rename sits unread until the key
        # expires. Nothing reads it: Receipt#load_secret resolves the secret
        # by secret_identifier alone (#4835).
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
              receipt_id: shortid,
              secret_id: secret.shortid,
              user: cust.obscure_email,
              action: 'deliver_email',
            }
          return
        end

        secret_logger.debug 'Preparing email delivery',
          {
            receipt_id: shortid,
            secret_id: secret.shortid,
            user: cust.obscure_email,
            action: 'deliver_email',
          }

        eaddrs = [eaddrs].flatten.compact[0..9] # Max 10

        eaddrs_safe     = eaddrs.collect { |e| OT::Utils.obscure_email(e) }
        eaddrs_safe_str = eaddrs_safe.join(', ')

        secret_logger.info 'Delivering secret by email',
          {
            receipt_id: shortid,
            secret_id: secret.shortid,
            user: cust.obscure_email,
            recipient_count: eaddrs_safe.size,
            recipients: eaddrs_safe_str,
            action: 'deliver_email',
          }
        recipients! eaddrs_safe_str

        if eaddrs.size > 1
          secret_logger.warn 'Multiple recipients detected',
            {
              receipt_id: shortid,
              secret_id: secret.shortid,
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
        # Blank ("") locales are truthy and slip past a bare `||`; treat as missing.
        locale = OT.default_locale if locale.to_s.strip.empty?

        Onetime::Jobs::Publisher.enqueue_email(
          :secret_link,
          {
            secret_key: secret.identifier,
            share_domain: secret.share_domain,
            recipient: email_address,
            sender_email: cust.email,
            has_passphrase: secret.has_passphrase?,
            locale: locale,
          },
          domain_id: domain_id,
        ) # fallback: :async_thread is the default
      end

      # Receipt transitions extend the state CAS with their accompanying fields
      # in the same Lua operation. There is no follow-up save that can overwrite
      # a concurrent display claim/memo or recreate a key removed after the CAS.
      # HGET rejects missing/terminal records; HSET preserves the existing expiry.
      # Only the winner updates its local projection and emits log/audit events.

      # MIGRATION NOTE: Replaces legacy `received!` method.
      # - Sets state to 'revealed' (was 'received')
      # - Sets `revealed` timestamp (legacy `received` kept for backward compat in safe_dump)
      # - Clears secret_identifier
      #
      # @param actor_context [Hash, nil] request-scoped audit context (e.g. the
      #   actor discriminator) threaded down from the reveal cascade (#3639).
      #   Forwarded to the org audit trail; nil fails safe to the 'unknown'
      #   actor (ADR-023; never misattributed to the creator). See
      #   #lifecycle_activity_attrs.
      # @return [Boolean, nil] true if THIS caller performed the transition;
      #   a falsy value if the in-memory guard or the atomic claim lost.
      def revealed!(actor_context: nil)
        # In-memory fast-path: short-circuit an already-terminal instance before
        # touching Redis. The authoritative, resurrection-proof guard is the CAS.
        return unless state?(:new) || state?(:previewed)

        now = Familia.now
        return unless compare_and_set_state!(
          :revealed,
          [:new, :previewed],
          revealed: now.to_i,
          secret_identifier: '',
          updated: now,
        )

        previous_state          = state
        original_secret_shortid = secret_identifier.to_s.slice(0, 8)
        self.state              = 'revealed'
        self.revealed           = now.to_i
        self.secret_identifier  = ''
        self.updated            = now

        secret_logger.info 'Receipt state transition to revealed',
          {
            receipt_id: shortid,
            secret_id: original_secret_shortid,
            previous_state: previous_state,
            new_state: 'revealed',
            timestamp: revealed,
          }

        # The audit event fires only inside the won-CAS branch, so the actor is
        # recorded exactly once; a race loser returned above and records nothing.
        record_org_secret_activity_event('revealed', **lifecycle_activity_attrs(actor_context))
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

        now = Familia.now
        return unless compare_and_set_state!(
          :orphaned,
          [:new, :previewed],
          secret_identifier: '',
          updated: now,
        )

        previous_state          = state
        original_secret_shortid = secret_identifier.to_s.slice(0, 8)
        self.state              = 'orphaned'
        self.updated            = now
        self.secret_identifier  = ''

        secret_logger.warn 'Receipt state transition to orphaned',
          {
            receipt_id: shortid,
            secret_id: original_secret_shortid,
            previous_state: previous_state,
            new_state: 'orphaned',
            timestamp: updated,
          }

        # A system-detected transition: no individual acted, so the event
        # carries the 'system' actor and never an actor_id (#3637).
        record_org_secret_activity_event('orphaned', 'actor' => 'system')
        true
      end

      # @param actor_context [Hash, nil] request-scoped audit context threaded
      #   down from the burn cascade (#3639); see #revealed! and
      #   #lifecycle_activity_attrs. nil fails safe to the 'unknown' actor
      #   (ADR-023).
      def burned!(actor_context: nil)
        # See guard comment on `revealed!` (was `received!`)
        return unless state?(:new) || state?(:previewed)

        now = Familia.now
        return unless compare_and_set_state!(
          :burned,
          [:new, :previewed],
          burned: now.to_i,
          secret_identifier: '',
          updated: now,
        )

        previous_state          = state
        original_secret_shortid = secret_identifier.to_s.slice(0, 8)
        self.state              = 'burned'
        self.burned             = now.to_i
        self.secret_identifier  = ''
        self.updated            = now

        secret_logger.info 'Receipt state transition to burned',
          {
            receipt_id: shortid,
            secret_id: original_secret_shortid,
            previous_state: previous_state,
            new_state: 'burned',
            timestamp: burned,
          }

        # Actor recorded exactly once inside the won-CAS branch (see revealed!).
        record_org_secret_activity_event('burned', **lifecycle_activity_attrs(actor_context))
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

        now = Familia.now
        return unless compare_and_set_state!(
          :expired,
          [:new, :previewed],
          secret_identifier: '',
          updated: now,
        )

        previous_state          = state
        original_secret_shortid = secret_identifier.to_s.slice(0, 8)
        self.state              = 'expired'
        self.updated            = now
        self.secret_identifier  = ''

        secret_logger.info 'Receipt state transition to expired',
          {
            receipt_id: shortid,
            secret_id: original_secret_shortid,
            previous_state: previous_state,
            new_state: 'expired',
            timestamp: updated,
            secret_ttl: secret_ttl,
            age_seconds: age,
          }

        # System-detected, like orphaned!: 'system' actor, never an actor_id.
        record_org_secret_activity_event('expired', 'actor' => 'system')
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

      # Pass the request-scoped actor context threaded into a lifecycle
      # transition (revealed!/burned!, #3639) through as string-keyed audit
      # attributes. Actor validation is centralized in
      # AccessTimeline#record_org_secret_activity_event so every event kind -- lifecycle,
      # fetch telemetry, receipt views, creation -- obeys the same rules
      # (fail-safe 'anonymous', no actor_id on anonymous/system events, full
      # untruncated objid for authenticated actors). Callers without request
      # context (v1 paths, account verification, direct receipt.revealed! test
      # calls) pass nothing and are recorded under the fail-safe actor.
      #
      # @param actor_context [Hash, nil] string- or symbol-keyed audit attrs.
      # @return [Hash] string-keyed attrs, empty when no context was threaded.
      def lifecycle_activity_attrs(actor_context)
        actor_context.is_a?(Hash) ? actor_context.transform_keys(&:to_s) : {}
      end

      RECEIPT_STATE_CAS_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], 'state')
        local from_count = tonumber(ARGV[1])
        for i = 2, from_count + 1 do
          if current == ARGV[i] then
            redis.call('HSET', KEYS[1], unpack(ARGV, from_count + 2))
            return 1
          end
        end
        return 0
      LUA
      private_constant :RECEIPT_STATE_CAS_SCRIPT

      # Receipt-local extension of StateCas: commit ONLY the transition's fields
      # together with its state. A separate field save, even without expiration
      # updates, would leave a deletion/expiry window after the state-only CAS.
      # Values use Familia's JSON storage encoding, not the HTTP safe_dump.
      def compare_and_set_state!(to_state, from_states, **fields)
        argv = [from_states.length]
        from_states.each { |from_state| argv << serialize_value(from_state.to_s) }
        fields.merge(state: to_state.to_s).each do |field, value|
          argv << field.to_s << serialize_value(value)
        end

        dbclient.eval(RECEIPT_STATE_CAS_SCRIPT, keys: [dbkey], argv: argv).to_i == 1
      end
    end
  end
end
