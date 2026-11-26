# lib/onetime/models/secret/features/secret_state_management.rb
#
# frozen_string_literal: true

require_relative '../../../jobs/publisher'

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
      # Secret kinds that are account mechanics rather than shared secrets.
      # Their reveal is the owner's own action (or a link sent to the owner),
      # so it never sends a reveal notice.
      VERIFICATION_KINDS = %w[account_verification password_reset email_change].freeze

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
      #   context keep working; a nil actor fails safe to 'unknown' (ADR-023),
      #   never misattributed to the creator.
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
      # A wrong-key decrypt (Familia::EncryptionError — the SECRET changed
      # under existing data, C10/QS-6) must not burn the secret: the claim is
      # rolled back so the record and ciphertext survive, and the secret is
      # claimable again the moment the key is restored. Zero plaintext was
      # produced, so returning the claim cannot violate ADR-019's
      # at-most-once display.
      #
      # @param passphrase_input [String, nil] passphrase supplied by the caller,
      #   forwarded to decryption.
      # @param actor_context [Hash, nil] request-scoped audit context forwarded
      #   to the receipt cascade / org audit trail (#3639); see {#revealed!}.
      # @return [String, nil] the decrypted plaintext for the single winning
      #   caller; nil for a loser or an already-terminal secret.
      # @raise [Onetime::SecretUndecryptable] when the ciphertext cannot be
      #   decrypted with the running key; the reveal claim has been rolled
      #   back and the secret remains revealable once the key is restored.
      def reveal!(passphrase_input: nil, actor_context: nil)
        prior_state = state # 'new' or 'previewed', read before the CAS
        return unless win_reveal_claim!

        # Decrypt from the still-in-memory ciphertext BEFORE consume clears it.
        begin
          plaintext = decrypted_secret_value(passphrase_input: passphrase_input)
        rescue Familia::EncryptionError
          # Zero plaintext was produced: returning the claim cannot violate
          # ADR-019's at-most-once display. Only the claim holder can be in
          # :revealed here, so the CAS back cannot race another winner. The
          # CAS is a pure Redis Lua boolean (state_cas.rb) that never touches
          # memory state, so @state must be restored explicitly.
          compare_and_set_state!(prior_state, [:revealed])
          @state = prior_state
          record_reveal_failed_undecryptable(actor_context)
          raise Onetime::SecretUndecryptable
        end

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

        begin
          md = load_receipt
          md.burned!(actor_context: actor_context) unless md.nil?
        ensure
          # A receipt failure must not skip destruction after the secret's
          # terminal claim. The exception still propagates; no success is sent.
          @state           = 'burned'
          @ciphertext      = nil
          @passphrase_temp = nil
          destroy_terminal_record!
        end
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

      # Best-effort observability for a rolled-back reveal (C10): fan the
      # event out to the org audit trail through the receipt, same
      # rescue-and-log posture as the rest of AccessTimeline — a failure here
      # must never mask the SecretUndecryptable the caller is about to see.
      # The actor context reveal! already threads rides along so even a
      # failed attempt is attributed (#3637); validation is centralized in
      # AccessTimeline#record_org_secret_activity_event.
      def record_reveal_failed_undecryptable(actor_context = nil)
        attrs = actor_context.is_a?(Hash) ? actor_context.transform_keys(&:to_s) : {}
        load_receipt&.record_org_secret_activity_event('reveal_failed_undecryptable', **attrs)
      rescue StandardError => ex
        OT.le "[reveal-rollback] #{ex.class}: #{ex.message} (secret=#{shortid})"
        nil
      end

      # Post-claim consumption shared by {#revealed!} and {#reveal!}: cascade
      # the receipt to revealed, destroy the record, then send the owner's
      # reveal notice. Assumes the caller has already won the claim via
      # {#win_reveal_claim!}.
      #
      # This is the single point every reveal path reaches (v1 ShowSecret,
      # v2/v3 RevealSecret and ShowSecret, account verification), so the
      # secret_revealed notice is sent here rather than in each controller.
      # It goes out only when the receipt's own CAS reports this caller as
      # the one that moved it to revealed, so one reveal sends one notice.
      # It is sent after destroy_terminal_record!, outside the MULTI/EXEC
      # that destroy! runs, and never raises (#notify_owner_of_reveal).
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
        notice          = nil
        receipt_claimed = false
        begin
          md = load_receipt
          unless md.nil?
            # Read before destroy! so the notice does not depend on what the
            # destroyed instance still holds in memory.
            notice          = reveal_notice_snapshot(md)
            receipt_claimed = md.revealed!(actor_context: actor_context) ? true : false
          end
        ensure
          # Once claimed and decrypted, destruction is independent of receipt
          # bookkeeping. Preserve fail-closed error propagation, not a retry.
          @state           = 'revealed'
          @ciphertext      = nil
          @passphrase_temp = nil
          destroy_terminal_record!
        end
        # The receipt CAS is the single-winner gate for the notice. A reveal
        # whose receipt is missing, or whose receipt another caller already
        # moved, sends no notice: that is intended, so that one reveal never
        # sends two.
        notify_owner_of_reveal(notice) if receipt_claimed && notice
        nil
      end

      # Reads in-memory fields only. It runs after the claim is won and before
      # the destroy, so it must not raise: a failure here skips the notice,
      # never the destroy.
      #
      # @param receipt [Onetime::Receipt] this secret's loaded receipt, for
      #   the domain_id and org_id recorded at creation
      # @return [Hash, nil] what #notify_owner_of_reveal needs, read up front
      def reveal_notice_snapshot(receipt)
        {
          owner_id: owner_id,
          shortid: shortid,
          share_domain: share_domain,
          domain_id: receipt.domain_id,
          org_id: receipt.org_id,
          verification: verification? || VERIFICATION_KINDS.include?(kind.to_s),
        }
      rescue StandardError => ex
        OT.le "[reveal-notice] snapshot failed: #{ex.class}"
        nil
      end

      # Email the owner that their secret was revealed, when they opted in.
      #
      # The payload names the secret by its short id only: the secret and
      # receipt identifiers are bearer capabilities and never go by email.
      # domain_id is the receipt's stored one, while it still names the same
      # domain for the same organization (Receipt.sender_domain_id_for), so a
      # secret shared from a custom domain is announced from that domain's
      # sender and never from a later holder of the name. share_domain
      # itself stays out of the payload: it would move the layout's header
      # and footer links to the custom domain (brand_baseuri), while this
      # account notice links the owner to settings on the canonical host.
      #
      # A failure is logged and swallowed: the reveal has already happened
      # and its response must not depend on a notification.
      #
      # @param notice [Hash] from #reveal_notice_snapshot
      # @return [void]
      def notify_owner_of_reveal(notice)
        return if notice[:verification]
        return if notice[:owner_id].to_s.empty? || notice[:owner_id].to_s == 'anon'

        owner = Onetime::Customer.load(notice[:owner_id])
        return if owner.nil? || owner.anonymous?
        return if owner.email.to_s.empty?
        # Mail goes only to an address the owner has proven they control
        # (ADR-051 decision 6: notification flows send only when the
        # contact address meets the verification policy). An unverified
        # owner is a silent skip, never an error.
        return unless owner.verified?
        return unless owner.notify_on_reveal?

        # Blank ("") locales are truthy and slip past a bare `||`.
        locale    = owner.locale.to_s.strip.empty? ? OT.default_locale : owner.locale
        domain_id = Onetime::Receipt.sender_domain_id_for(
          domain_id: notice[:domain_id], org_id: notice[:org_id], share_domain: notice[:share_domain],
        )

        Onetime::Jobs::Publisher.enqueue_email(
          :secret_revealed,
          {
            recipient: owner.email,
            secret_shortid: notice[:shortid],
            revealed_at: Time.now.utc.iso8601,
            locale: locale,
          },
          domain_id: domain_id,
        )
      rescue StandardError => ex
        OT.le "[reveal-notice] #{ex.class}: #{ex.message} (secret=#{notice&.dig(:shortid)})"
        nil
      end

      # Destroys the record after a terminal claim. Clearing @ciphertext above
      # only clears this instance; when destroy! raises, the stored hash would
      # keep the payload until its TTL. So the payload fields are struck from
      # the stored hash before the destroy! error propagates. The strike is
      # best effort: an unreachable datastore fails it too, and the original
      # error (with its cause) is what the caller sees either way.
      #
      # @return [void]
      def destroy_terminal_record!
        destroy!
      rescue StandardError => ex
        strike_stored_payload!(ex)
        raise
      end

      # HDEL of the encrypted payload (`ciphertext`) and the pre-Familia-v2
      # `value` field. HDEL on a missing key or field is a no-op, so a destroy!
      # that removed the hash before raising is harmless here. Does not raise.
      def strike_stored_payload!(destroy_error)
        dbclient.hdel(dbkey, 'ciphertext', 'value')
      rescue StandardError => ex
        OT.le "[secret-destroy] payload strike failed after #{destroy_error.class}: #{ex.class} (secret=#{shortid})"
        nil
      end
    end
  end
end
