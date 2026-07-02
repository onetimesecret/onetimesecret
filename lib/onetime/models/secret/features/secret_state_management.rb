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
      #
      # Records that the secret link was accessed (but not yet consumed) by
      # flipping state :new -> :previewed with an atomic, NON-creating CAS.
      # Unlike the former save_fields(:state) -- an unconditional HSET that
      # recreates the key if absent -- this transition:
      #   * cannot resurrect a secret a concurrent reveal/burn already
      #     destroyed (HGET on a missing key matches nothing), and
      #   * cannot revert a secret that has already reached a terminal state
      #     (it fires only from :new); the old unconditional write could briefly
      #     revert a revealed-but-not-yet-destroyed record to :previewed and
      #     re-open viewability while its ciphertext still existed.
      # It also no longer resets the secret's TTL on preview: a merely-viewed
      # link must not extend a burn-after-reading secret's lifetime -- which is
      # both safer and what this method's comment always claimed to do.
      def previewed!
        # Fast-path guard on in-memory state; the CAS below is the authority.
        return unless state?(:new)

        return unless compare_and_set_state!(:previewed, [:new])

        @state = 'previewed'
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
      # {#compare_and_set_state!} closes that race with an atomic
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
        unless compare_and_set_state!(:revealed, [:new, :previewed])
          # Lost the race: a concurrent caller already terminalized this
          # secret. Mark THIS in-memory instance terminal so its viewable? and
          # safe_dump reflect reality; the plaintext is withheld by returning
          # false, which the reveal controllers gate on. (previewed! is itself
          # non-resurrecting now, so this is about presenting accurate loser
          # state, not the sole guard against re-creating the destroyed key.)
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
        return false unless compare_and_set_state!(:burned, [:new, :previewed])

        md               = load_receipt
        md.burned! unless md.nil?
        @passphrase_temp = nil
        destroy!
        true
      end

      # Backward compatibility aliases for legacy method names
      alias viewed! previewed!
      alias received! revealed!

      # Lua compare-and-set on the +state+ field, run atomically by Redis (its
      # command loop is single-threaded). Sets state to ARGV[1] iff the current
      # value equals one of ARGV[2..]. Returns 1 to the single caller that
      # performs the flip, 0 to everyone else -- including when the key/field is
      # gone (HGET yields a Lua false that matches nothing, so a destroyed
      # record is never resurrected) and when the state has already advanced
      # (so a terminal state is never reverted).
      STATE_CAS_SCRIPT = <<~LUA
        local current = redis.call('HGET', KEYS[1], 'state')
        for i = 2, #ARGV do
          if current == ARGV[i] then
            redis.call('HSET', KEYS[1], 'state', ARGV[1])
            return 1
          end
        end
        return 0
      LUA

      private

      # Atomically transition the persisted +state+ field from one of
      # +from_states+ to +to_state+, returning whether THIS caller performed
      # the flip. This is the single concurrency primitive behind every state
      # transition on a Secret; each caller documents what its own transition
      # guards against.
      #
      # Because Redis executes the Lua script atomically, of any number of
      # racing callers exactly one observes an allowed +from+ value and flips
      # it. This is the same compare-and-set idiom Familia's
      # {Familia::Lock#release} uses, reached through the connection resolver
      # via +dbclient+ -- but on the record's own +state+ field rather than a
      # separate lock key, so there is no second key, no TTL, and no expiry
      # window where a slow critical section outlives the lock and a second
      # caller slips in. It fails closed: a missing key (destroyed) or an
      # already-advanced state simply loses, so the transition can neither
      # resurrect nor revert a record.
      #
      # Operands are produced with #serialize_value so they match how +state+
      # is encoded at rest (Familia JSON-encodes scalar fields for type
      # preservation), rather than hard-coding the on-disk representation here.
      #
      # @param to_state [Symbol, String] state to set on success.
      # @param from_states [Array<Symbol, String>] states the flip may fire from.
      # @return [Boolean] true iff this caller performed the transition.
      def compare_and_set_state!(to_state, from_states)
        argv = [serialize_value(to_state.to_s)]
        from_states.each { |state| argv << serialize_value(state.to_s) }

        dbclient.eval(STATE_CAS_SCRIPT, [dbkey], argv).to_i == 1
      end
    end
  end
end
