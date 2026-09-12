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
      # unverified. See Onetime::Customer::VERIFIED_BY_VALUES for the full
      # list of in-use values and where each is written.
      base.field :verified_by

      # Set ONLY at OmniAuth JIT provisioning (config/hooks/omniauth.rb) when
      # the IdP explicitly asserted email_verified: false (or the claim could
      # not be read — that path fails closed). It records WHY an sso_jit
      # customer was left unverified, so the customers doctor's
      # :sso_customer_unverified check can tell a record that drifted (auto-
      # repairable: mirror the Verified accounts row) from one the IdP vetoed
      # (never auto-repaired: an operator must verify by hand). Written once
      # at creation; nothing rewrites it. nil / absent reads as not vetoed.
      base.boolean_field :sso_email_unverified

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
      # Refuse an unknown verified_by provenance tag before anything is
      # written. nil/blank is NOT rejected here: it is the stored form of
      # "no provenance" (unverified, or a pre-tag record the doctor's
      # verified_by repair backfills as 'legacy'), and callers that clear
      # verification pass it deliberately.
      #
      # @param value [String, nil] candidate verified_by tag
      # @raise [ArgumentError] when value is present and not one of
      #   Onetime::Customer::VERIFIED_BY_VALUES
      # @return [void]
      def assert_known_verified_by!(value)
        return if value.nil? || value.to_s.empty?
        return if Onetime::Customer::VERIFIED_BY_VALUES.include?(value.to_s)

        raise ArgumentError,
          "Unknown verified_by provenance #{value.inspect}; " \
          "expected one of: #{Onetime::Customer::VERIFIED_BY_VALUES.join(', ')}"
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

      # Check if account was created via Stripe payment (not email verified)
      def payment_verified?
        verified? && verified_by.to_s == 'stripe_payment'
      end

      # Did the IdP veto the verified stamp at SSO JIT provisioning? Same
      # canonical 'true' / 'false' storage as verified?, so a plain string
      # equality check; nil (every non-SSO record, and SSO records that
      # predate the field) reads as not vetoed.
      def sso_email_unverified?
        sso_email_unverified == 'true'
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
    end

    Familia::Base.add_feature self, :status
  end
end
