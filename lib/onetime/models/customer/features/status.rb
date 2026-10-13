# lib/onetime/models/customer/features/status.rb
#
# frozen_string_literal: true

require_relative '../../field_types'

module Onetime::Customer::Features
  module Status
    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Pull in the BooleanFieldMacro so `boolean_field :verified` becomes
      # available alongside the standard `field` declarations. This is the
      # Familia-idiomatic equivalent of the upstream `encrypted_field`
      # macro: a custom FieldType handles canonicalization at the type
      # level, so callers cannot bypass it via the setter, the fast
      # writer, or by passing the field through Customer.create!.
      base.extend Onetime::Models::FieldTypes::BooleanFieldMacro

      base.field :role
      base.field :joined
      base.boolean_field :verified
      # Provenance tag for how the account became verified; nil when
      # unverified. See Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY
      # for the full list of in-use values and where each is written.
      base.field :verified_by

      # Why an sso_jit customer was left unverified at JIT provisioning; one
      # of Onetime::Customer::VERIFICATION_HOLDS, nil when nothing was
      # withheld (every non-SSO record, SSO records that predate the field,
      # and SSO records that were verified at creation). Set once by the
      # OmniAuth JIT hook via EnsureCustomerForAccount and never rewritten,
      # so the customers doctor can tell a record that drifted (auto-
      # repairable: mirror the Verified accounts row) from one where
      # verification was withheld on purpose (never auto-repaired; an
      # operator verifies by hand once the address is confirmed).
      base.field :verification_hold

      # Reversible trust & safety pause (NOT a role, NOT destructive).
      # A suspended customer keeps all of their data but cannot authenticate:
      # login rejects them and BaseSessionAuthStrategy refuses their sessions.
      # Managed exclusively via the audited SetSuspension op (colonel API);
      # see Auth::Operations::Customers::SetSuspension.
      base.boolean_field :suspended
      base.field :suspended_at      # Unix timestamp when the suspension was applied
      base.field :suspended_by      # acting admin's PUBLIC id (extid), never an objid
      base.field :suspended_reason  # optional operator-supplied reason
    end

    module ClassMethods
      # Refuse an unknown verification_hold before anything is written. nil /
      # blank is the stored form of "nothing withheld" and is accepted.
      #
      # @param value [String, Symbol, nil] candidate hold reason
      # @raise [ArgumentError] when value is present and not one of
      #   Onetime::Customer::VERIFICATION_HOLDS
      # @return [void]
      def assert_known_verification_hold!(value)
        return if value.nil? || value.to_s.empty?
        return if Onetime::Customer::VERIFICATION_HOLDS.include?(value.to_s)

        raise ArgumentError,
          "Unknown verification_hold #{value.inspect}; " \
          "expected one of: #{Onetime::Customer::VERIFICATION_HOLDS.keys.join(', ')}"
      end
    end

    module InstanceMethods
      # Stored form is canonical 'true' / 'false' (see
      # Onetime::Models::FieldTypes::BooleanFieldType), so the predicate is a
      # plain string equality check — no truthy-table, no `to_s.downcase`.
      def verified?
        !anonymous? && verified == 'true'
      end

      # Check if account was verified via email confirmation
      def email_verified?
        verified? && verified_by.to_s == 'email'
      end

      # Does the record carry proof that this person controls the mailbox?
      # True only for the provenances in Onetime::Customer::MAILBOX_VERIFIED_BY.
      # An IdP-asserted ('sso'), payment, autoverify or legacy stamp satisfies
      # verified? but not this (#4735). Fail-closed on a blank provenance.
      def mailbox_verified?
        verified? && Onetime::Customer::MAILBOX_VERIFIED_BY.include?(verified_by.to_s)
      end

      # Does revealing this verification secret prove control of THIS
      # customer's current mailbox? The account-verification and password-
      # reset links are delivered to the customer's address, so yes. The
      # email-change confirmation link is delivered to the PROPOSED address,
      # so no: a customer without mailbox proof must not be able to mint it
      # for their current address by confirming a change to one they do
      # control.
      #
      # The secret identifies itself (Secret#kind): 'email_change' is never
      # proof; Secret::MAILBOX_PROOF_KINDS always is. A secret minted before
      # the kind was recorded is classified by how it was minted: only
      # send_verification_email mints a receipt-backed verification secret
      # (Receipt.spawn_pair), so a receipt marks the account-verification
      # link; a receiptless one is a password-reset or an email-change secret
      # and counts only while it is the link this account recorded as its
      # own (reset_secret). A missing or mismatched pointer is never proof:
      # the pointers can only narrow the answer. An unrecorded legacy
      # email-change secret — a second request overwrote the pointer, or a
      # crash landed between the two writes — stays live until it expires
      # and must not read as proof of the current address.
      #
      # @param secret [Onetime::Secret] a secret flagged verification
      # @return [Boolean]
      def mailbox_proof_secret?(secret)
        kind = secret.kind.to_s
        return false if kind == 'email_change'
        return false if verification_pointer_names?(pending_email_change, secret)
        return true if Onetime::Secret::MAILBOX_PROOF_KINDS.include?(kind)

        # Blank kind: minted before the kind was recorded.
        return true unless secret.receipt_identifier.to_s.empty?

        verification_pointer_names?(reset_secret, secret)
      end

      # Does reset_secret name a live password-recovery token?
      #
      # The pointer is shared: send_verification_email records the welcome
      # link there too, and a duplicate signup or an unverified sign-in can
      # resend verification while the account holder has a recovery link out.
      # Overwriting the pointer then fails that link at redemption (#4735
      # review, F6), so a resend asks here first. An empty or dangling pointer,
      # or one naming an earlier verification link, is free to overwrite. A
      # kind-less secret is classified as mailbox_proof_secret? does: receipt-
      # backed is a verification link, receiptless is a recovery token.
      #
      # @param recorded [String] the pointer value to classify; defaults to a
      #   fresh read. A caller that goes on to write passes the value it read
      #   so the write can be conditioned on it (record_verification_pointer!).
      # @return [Boolean]
      def reset_secret_outstanding?(recorded = reset_secret.value.to_s)
        recorded = recorded.to_s
        return false if recorded.empty?

        current = Onetime::Secret.load(recorded)
        return false if current.nil?

        kind = current.kind.to_s
        return kind != 'account_verification' unless kind.empty?

        current.receipt_identifier.to_s.empty?
      end

      # Record a freshly minted verification link as reset_secret, unless the
      # pointer names a live recovery token.
      #
      # The outstanding check and the write are two round trips, so a recovery
      # request can land between them and its token would be lost to the
      # welcome link (#4735 review, F6 concurrent). The write is a compare-
      # and-set against the value the check classified: if the pointer moved
      # in between, whatever moved it keeps it and the welcome link goes out
      # unrecorded — it is mailbox proof by its kind either way.
      #
      # @param secret [Onetime::Secret] the account-verification secret
      # @return [Boolean] true when the pointer now names the secret
      def record_verification_pointer!(secret)
        recorded = reset_secret.value.to_s
        return false if reset_secret_outstanding?(recorded)

        claim_reset_pointer(secret.identifier, expected: recorded)
      end

      # Check if account was created via Stripe payment (not email verified)
      def payment_verified?
        verified? && verified_by.to_s == 'stripe_payment'
      end

      # Was verification deliberately withheld at SSO JIT provisioning?
      # True when verification_hold carries a reason (see
      # Onetime::Customer::VERIFICATION_HOLDS); nil / blank reads as not
      # held. Independent of verified?: an operator who verifies a held
      # record by hand leaves the hold in place as history.
      def verification_held?
        !verification_hold.to_s.empty?
      end

      # Reversible trust & safety pause. Stored form is canonical
      # 'true' / 'false' (BooleanFieldType), so — like verified? — the
      # predicate is a plain string equality check. nil (records that
      # predate the field) reads as not suspended.
      def suspended?
        !anonymous? && suspended == 'true'
      end

      def active?
        # We modify the role when destroying so if a customer is verified
        # and has a role of 'customer' then they are active. A suspended
        # account is never active: suspension is a reversible trust & safety
        # pause enforced consistently at every access gate (auth strategies,
        # org/workspace behavior), so anything gating on active? honors it too.
        verified? && role?('customer') && !suspended?
      end

      def pending?
        # A customer is considered pending if they are not anonymous, not verified,
        # and have a role of 'customer'. If any one of these conditions is changes
        # then the customer is no longer pending.
        !anonymous? && !verified? && role?('customer') # we modify the role when destroying
      end

      private

      # Does this standalone pointer (reset_secret / pending_email_change)
      # currently name the given secret? Blank pointer: no.
      #
      # @param pointer [Familia::StringKey]
      # @param secret [Onetime::Secret]
      # @return [Boolean]
      def verification_pointer_names?(pointer, secret)
        recorded = pointer.value.to_s
        !recorded.empty? && recorded == secret.identifier.to_s
      end
    end

    Familia::Base.add_feature self, :status
  end
end
