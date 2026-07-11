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
      # Consume the secret WITHOUT returning its plaintext. For callers that
      # only need to mark the secret revealed and expunge it -- e.g. account
      # verification, or the legacy v1 flow which decrypts separately and then
      # gates its own output. Read controllers that must hand back the plaintext
      # should prefer {#reveal!}, which cannot be decoupled from the claim.
      #
      # @param actor_context [Hash, nil] request-scoped audit context (the actor
      #   discriminator) forwarded to the receipt cascade and, from there, the
      #   org audit trail (#3639). Defaults to nil so callers without request
      #   context (v1, account verification) keep working; a nil actor is
      #   recorded as anonymous/unknown, never misattributed to the creator.
      # @return [Boolean] true if THIS caller performed the reveal, false if a
      #   concurrent caller won the race or the secret was already terminal.
      def revealed!(actor_context: nil)
        return false unless win_reveal_claim!

        consume_after_reveal!(actor_context: actor_context)
        true
      end

      # Reveal-and-fetch: atomically claim the one-shot reveal and, ONLY on
      # winning, decrypt and return the plaintext; then cascade the receipt and
      # destroy the record. A losing (or already-terminal) caller gets +nil+.
      #
      # This is the plaintext-returning sibling of {#revealed!} and the
      # preferred entry point for read controllers: because decryption happens
      # inside the won-claim branch, a caller cannot obtain the plaintext
      # without also winning the single permitted reveal. There is no separate
      # "decrypt" step for a controller to forget to gate -- the burn-after-
      # reading invariant is enforced here by construction rather than by each
      # call site remembering to check a boolean.
      #
      # @param passphrase_input [String, nil] passphrase supplied by the caller,
      #   forwarded to decryption.
      # @param actor_context [Hash, nil] request-scoped audit context forwarded
      #   to the receipt cascade / org audit trail (#3639); see {#revealed!}.
      # @return [String, nil] the decrypted plaintext for the single winning
      #   caller; nil for a loser or an already-terminal secret.
      def reveal!(passphrase_input: nil, actor_context: nil)
        return unless win_reveal_claim!

        # Decrypt from the still-in-memory ciphertext BEFORE consume clears it.
        plaintext = decrypted_secret_value(passphrase_input: passphrase_input)
        consume_after_reveal!(actor_context: actor_context)
        plaintext
      end

      # @param actor_context [Hash, nil] request-scoped audit context forwarded
      #   to the receipt cascade / org audit trail (#3639); see {#revealed!}.
      # @return [Boolean] true if THIS caller performed the burn, false if a
      #   concurrent caller won the race or the secret was already terminal.
      def burned!(actor_context: nil)
        # A guard to allow only a fresh, new secret to be burned. Also ensures that
        # we don't support going from :burned back to something else.
        return false unless state?(:new) || state?(:previewed)

        # Atomic gate: see revealed!. A double-burn is not a plaintext leak,
        # but the CAS still guarantees the receipt cascade and any caller-side
        # bookkeeping (e.g. secrets_burned counters) happen exactly once.
        return false unless compare_and_set_state!(:burned, [:new, :previewed])

        md               = load_receipt
        md.burned!(actor_context: actor_context) unless md.nil?
        @passphrase_temp = nil
        destroy!
        true
      end

      # Backward compatibility aliases for legacy method names
      alias received! revealed!

      private

      # The atomic +state+ compare-and-set these transitions claim through
      # (+compare_and_set_state!+) is provided by the shared +state_cas+
      # feature; see Onetime::Models::Features::StateCas.

      # Atomic claim shared by {#revealed!} and {#reveal!}. Returns true iff
      # THIS caller won the one-and-only reveal. This is the recipient-reveal
      # claim in ADR-019 (At-Most-Once Secret Reveal); a bare decrypt-and-return
      # that bypasses it silently reintroduces multi-reveal. On loss (a concurrent caller
      # already terminalized the secret) it marks the in-memory instance
      # terminal so its viewable?/safe_dump reflect reality and its plaintext
      # stays withheld; the in-memory check above is a cheap fast-path before
      # touching Redis. (previewed! is itself non-resurrecting, so marking
      # state here is about presenting accurate loser state, not the sole guard
      # against re-creating the destroyed key.)
      #
      # @return [Boolean] true iff this caller performed the state transition.
      def win_reveal_claim!
        return false unless state?(:new) || state?(:previewed)

        unless compare_and_set_state!(:revealed, [:new, :previewed])
          # Lost the claim: mark the instance terminal so viewable?/safe_dump
          # reflect reality and the ciphertext is withheld.
          @state      = 'revealed'
          @ciphertext = nil
          return false
        end

        # Won the claim: reflect the persisted transition in memory now so a
        # state?/viewable? read between the claim and consume_after_reveal! is
        # accurate (no winner/loser asymmetry). Ciphertext is intentionally
        # retained here so reveal! can still decrypt; consume clears it.
        @state = 'revealed'
        true
      end

      # Post-claim consumption shared by {#revealed!} and {#reveal!}: cascade
      # the receipt to revealed and destroy the record. Assumes the caller has
      # already won the claim via {#win_reveal_claim!}.
      #
      # The in-memory state is set to 'revealed' even though the record is about
      # to be destroyed: state drives viewable?, so leaving it revealable would
      # keep a just-consumed instance readable. Ciphertext is cleared so the
      # payload is not recoverable from this instance; other fields (state,
      # lifespan, ...) remain for safe_dump / success_data.
      #
      # @param actor_context [Hash, nil] request-scoped audit context forwarded
      #   to the receipt's revealed! cascade (#3639); see {#revealed!}.
      # @return [void]
      def consume_after_reveal!(actor_context: nil)
        md = load_receipt
        md.revealed!(actor_context: actor_context) unless md.nil?

        @state           = 'revealed'
        @ciphertext      = nil
        @passphrase_temp = nil
        destroy!
      end
    end
  end
end
