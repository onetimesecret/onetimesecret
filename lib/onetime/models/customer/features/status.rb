# lib/onetime/models/customer/features/status.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  module Status
    # Truthy representations of the `verified` field. Writes are coerced to
    # canonical 'true' / 'false' strings (see Coercion below); reads remain
    # tolerant of legacy values like '1' (written by older code paths) so
    # existing customers do not require a manual Redis migration.
    TRUTHY_VERIFIED_VALUES = %w[true 1].freeze
    private_constant :TRUTHY_VERIFIED_VALUES

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field :role
      base.field :joined
      base.field :verified
      base.field :verified_by  # 'email', 'stripe_payment', 'autoverify', nil

      # Prepended AFTER `field :verified` so `super` reaches the
      # Familia-generated writer. This guarantees every write — whether via
      # `cust.verified = …`, `Customer.create!(verified: …)`, or the fast
      # writer `cust.verified!(…)` — is normalized to the canonical string
      # form expected by `verified?`.
      base.prepend Coercion
    end

    def self.canonical_verified(value)
      truthy_verified?(value) ? 'true' : 'false'
    end

    def self.truthy_verified?(value)
      TRUTHY_VERIFIED_VALUES.include?(value.to_s.downcase)
    end

    module Coercion
      def verified=(value)
        super(Status.canonical_verified(value))
      end
    end

    module ClassMethods
    end

    module InstanceMethods
      def verified?
        !anonymous? && Status.truthy_verified?(verified)
      end

      # Check if account was verified via email confirmation
      def email_verified?
        verified? && verified_by.to_s == 'email'
      end

      # Check if account was created via Stripe payment (not email verified)
      def payment_verified?
        verified? && verified_by.to_s == 'stripe_payment'
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
