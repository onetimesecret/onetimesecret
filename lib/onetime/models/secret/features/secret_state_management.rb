# lib/onetime/models/secret/features/secret_state_management.rb
#
# frozen_string_literal: true

module Onetime::Secret::Features
  module SecretStateManagement
    Familia::Base.add_feature self, :secret_state_management

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
      def generate_id
        Familia.generate_id
      end

      def count
        instances.count # e.g. zcard dbkey
      end
    end

    module InstanceMethods
      def state?(guess)
        state.to_s.eql?(guess.to_s)
      end

      def viewable?
        # Important: check Familia v2 field (ciphertext) first so that a non-empty
        # value field doesn't interfere with the current v2 happy path
        (key?(:ciphertext) || key?(:value)) && (state?(:new) || state?(:previewed))
      end

      def receivable?
        # Important: See note in viewable?
        (key?(:ciphertext) || key?(:value)) && (state?(:new) || state?(:previewed))
      end

      # MIGRATION NOTE: This method replaces the legacy `viewed!` method.
      # Existing data with state='viewed' should be migrated to state='previewed'.
      # The `viewed` timestamp field maps to the new `previewed` field.
      def previewed!
        # A guard to prevent regressing (e.g. from :burned back to :previewed)
        return unless state?(:new)

        # The secret link has been accessed but the secret has not been consumed yet
        @state = 'previewed'
        # Only save the state field — a full save would re-serialize encrypted
        # fields (ciphertext), corrupting them via double-encryption. Using
        # save_fields also avoids resetting the TTL.
        save_fields(:state)
      end

      # MIGRATION NOTE: This method replaces the legacy `received!` method.
      # Existing data with state='received' should be migrated to state='revealed'.
      # The `received` timestamp field maps to the new `revealed` field.
      #
      # Burn-after-reading is the core product promise: a secret must be
      # revealed to at most ONE caller. Two concurrent reveal requests both
      # load the same secret, both read an in-memory state of :new/:previewed,
      # and -- without an atomic guard -- both pass the check below, both
      # decrypt, and both destroy, handing the plaintext to two clients.
      #
      # {#claim_terminal_transition!} closes that race with an atomic
      # compare-and-set in Redis: of any number of racing callers, exactly one
      # wins the claim and is permitted to reveal; the rest get +false+ and
      # must not emit the plaintext (the reveal controllers gate on this
      # return value). The in-memory check is kept as a cheap fast-path that
      # short-circuits an already-terminal instance before touching Redis.
      #
      # @return [Boolean] true if THIS caller performed the reveal, false if a
      #   concurrent caller won the race or the secret was already terminal.
      def revealed!
        # A guard to allow only a fresh, new secret to be revealed. Also ensures that
        # we don't support going from :previewed back to something else.
        return false unless state?(:new) || state?(:previewed)

        # Atomic gate: only the caller that wins the compare-and-set proceeds.
        unless claim_terminal_transition!(:revealed)
          # Lost the race: a concurrent caller already terminalized (and is
          # destroying) this secret. Mark THIS in-memory instance terminal so
          # (a) it is no longer viewable? and (b) a downstream
          # `previewed! if state?(:new)` cannot fire -- that would HSET the
          # `state` field and resurrect the key the winner just destroyed.
          # The pre-atomic code left every caller with state='revealed' for
          # the same reason; we preserve that invariant on the losing path.
          @state      = 'revealed'
          @ciphertext = nil
          return false
        end

        md               = load_receipt
        md.revealed! unless md.nil?
        # It's important for the state to change here, even though we're about to
        # destroy the secret. This is because the state is used to determine if
        # the secret is viewable. If we don't change the state here, the secret
        # will still be viewable b/c (state?(:new) || state?(:previewed) == true).
        @state           = 'revealed'
        # Clear ciphertext so the payload is not recoverable from this
        # instance. We don't clear arbitrary fields because safe_dump
        # and success_data still read state, lifespan, etc.
        @ciphertext      = nil
        @passphrase_temp = nil
        destroy!
        true
      end

      # @return [Boolean] true if THIS caller performed the burn, false if a
      #   concurrent caller won the race or the secret was already terminal.
      def burned!
        # A guard to allow only a fresh, new secret to be burned. Also ensures that
        # we don't support going from :burned back to something else.
        return false unless state?(:new) || state?(:previewed)

        # Atomic gate: see revealed!. A double-burn is not a plaintext leak,
        # but the CAS still guarantees the receipt cascade and any caller-side
        # bookkeeping (e.g. secrets_burned counters) happen exactly once.
        return false unless claim_terminal_transition!(:burned)

        md               = load_receipt
        md.burned! unless md.nil?
        @passphrase_temp = nil
        destroy!
        true
      end

      # Backward compatibility aliases for legacy method names
      alias viewed! previewed!
      alias received! revealed!

      # Lua compare-and-set, executed atomically by Redis. Returns 1 to the
      # single caller that moves +state+ out of a revealable value, 0 to
      # everyone else (including when the key or field is already gone, where
      # HGET returns a Lua false that matches neither revealable marker).
      CLAIM_TERMINAL_TRANSITION_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], 'state')
        if current == ARGV[1] or current == ARGV[2] then
          redis.call('HSET', KEYS[1], 'state', ARGV[3])
          return 1
        end
        return 0
      LUA

      private

      # Atomically claims the one-and-only terminal transition for this
      # secret, guarding against the double-reveal / double-burn race.
      #
      # Redis runs the Lua script atomically (its command loop is
      # single-threaded), so of any number of concurrent callers exactly one
      # can observe the persisted +state+ field as still revealable
      # (:new / :previewed) and flip it to the terminal marker. Every other
      # caller -- including one that arrives after the key has already been
      # destroyed, where HGET yields no value -- sees a non-revealable state
      # and loses. This is the same compare-and-set idiom Familia's
      # {Familia::Lock#release} uses, reached through the connection resolver
      # via +dbclient+.
      #
      # A CAS on +state+ rather than a Familia::Lock because the +state+ field
      # is its own winner token: no second key, no TTL, and no expiry window
      # where a slow reveal outlives the lock and a second caller slips in.
      # Once flipped, +state+ can never read as revealable again -- the guard
      # fails closed, as a one-shot security transition must. A mutex would
      # only serialize callers; it would still need this exact check inside it.
      #
      # The comparison operands are produced with #serialize_value so they
      # match exactly how the +state+ field is encoded at rest (Familia
      # JSON-encodes scalar fields for type preservation), rather than
      # hard-coding the on-disk representation here.
      #
      # @param claimed_state [Symbol, String] terminal marker to set
      #   (:revealed / :burned).
      # @return [Boolean] true if this caller won the claim, false otherwise.
      def claim_terminal_transition!(claimed_state)
        new_enc       = serialize_value('new')
        previewed_enc = serialize_value('previewed')
        claimed_enc   = serialize_value(claimed_state.to_s)

        outcome = dbclient.eval(
          CLAIM_TERMINAL_TRANSITION_SCRIPT,
          [dbkey],
          [new_enc, previewed_enc, claimed_enc],
        )
        outcome.to_i == 1
      end
    end
  end
end
