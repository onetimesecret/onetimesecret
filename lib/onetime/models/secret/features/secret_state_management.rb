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

      # Atomic single-winner consume claim (finding C1: the one-time guarantee
      # must hold under concurrency).
      #
      # A "one-time" secret must be revealable/burnable exactly once even when
      # simultaneous requests for the same identifier are served by separate
      # Puma worker PROCESSES (no shared GIL). The previous flow was a TOCTOU:
      # each request checked the in-memory state, decrypted, then destroyed —
      # so two requests could both pass the guard and both disclose the secret.
      #
      # This Lua script runs server-side and, in ONE atomic step, deletes the
      # secret's main hash key iff its state is still consumable (new/previewed),
      # returning 1 to the single caller that wins. All other concurrent callers
      # receive 0 and must treat the secret as already consumed (and MUST NOT
      # disclose its value).
      CONSUME_SCRIPT = <<~LUA
        local state = redis.call('HGET', KEYS[1], 'state')
        if state then
          -- Familia stores field values JSON-encoded, so a string field is
          -- quoted at rest (e.g. the literal characters "new"). Strip one
          -- layer of surrounding double quotes so this matches the Ruby-side
          -- state?(:new)/state?(:previewed) guard regardless of encoding.
          state = string.gsub(state, '^"(.*)"$', '%1')
        end
        if state == 'new' or state == 'previewed' then
          return redis.call('DEL', KEYS[1])
        end
        return 0
      LUA

      # @return [Boolean] true only for the single caller that atomically
      #   claimed (and deleted) the secret's main key; false if it was already
      #   consumed/expired by another request.
      def claim_consumption!
        dbclient.eval(CONSUME_SCRIPT, keys: [dbkey]).to_i == 1
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
      # Reveal-and-consume. Returns true ONLY for the single caller that wins
      # the atomic claim; concurrent/duplicate callers get false and must not
      # disclose the secret value (finding C1). Replaces the old non-atomic
      # state-check-then-destroy.
      def revealed!
        # Atomic winner-take-all claim. Subsumes the old in-memory state guard
        # (`return unless state?(:new) || state?(:previewed)`): the Lua check
        # is the authoritative, race-free version of that same guard.
        return false unless claim_consumption!

        md               = load_receipt
        md.revealed! unless md.nil?
        # Mirror the state transition in memory so this instance's viewable?
        # reflects reality for the rest of the request.
        @state           = 'revealed'
        # Clear ciphertext so the payload is not recoverable from this
        # instance. We don't clear arbitrary fields because safe_dump
        # and success_data still read state, lifespan, etc.
        @ciphertext      = nil
        @passphrase_temp = nil
        # The main key was already removed by the atomic claim above; destroy!
        # cleans up related fields / class indexes / instance registration. Its
        # own main-key delete is a harmless no-op here.
        destroy!
        true
      end

      # Burn-and-consume. Returns true ONLY for the single winning caller; a
      # concurrent reveal/burn that already consumed the secret yields false
      # (finding C1). Burning an already-consumed secret is a benign no-op.
      def burned!
        return false unless claim_consumption!

        md               = load_receipt
        md.burned! unless md.nil?
        @passphrase_temp = nil
        destroy!
        true
      end

      # Backward compatibility aliases for legacy method names
      alias viewed! previewed!
      alias received! revealed!
    end
  end
end
