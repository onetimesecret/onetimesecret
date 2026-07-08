# lib/onetime/models/customer/features/status.rb
#
# frozen_string_literal: true

require_relative '../../../field_types/boolean_field_type'

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
      base.extend Onetime::FieldTypes::BooleanFieldMacro

      base.field :role
      base.field :joined
      base.boolean_field :verified
      base.field :verified_by  # 'email', 'stripe_payment', 'autoverify', nil

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
    end

    module InstanceMethods
      # Stored form is canonical 'true' / 'false' (see
      # Onetime::FieldTypes::BooleanFieldType), so the predicate is a
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

      # Reversible trust & safety pause. Stored form is canonical
      # 'true' / 'false' (BooleanFieldType), so — like verified? — the
      # predicate is a plain string equality check. nil (records that
      # predate the field) reads as not suspended.
      def suspended?
        !anonymous? && suspended == 'true'
      end

      def active?
        # We modify the role when destroying so if a customer is verified
        # and has a role of 'customer' then they are active.
        verified? && role?('customer')
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
