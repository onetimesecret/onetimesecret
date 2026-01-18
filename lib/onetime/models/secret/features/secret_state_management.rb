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
        key?(:value) && (state?(:new) || state?(:previewed))
      end

      def receivable?
        key?(:value) && (state?(:new) || state?(:previewed))
      end

      # MIGRATION NOTE: This method replaces the legacy `viewed!` method.
      # Existing data with state='viewed' should be migrated to state='previewed'.
      # The `viewed` timestamp field maps to the new `previewed` field.
      def previewed!
        # A guard to prevent regressing (e.g. from :burned back to :previewed)
        return unless state?(:new)

        # The secret link has been accessed but the secret has not been consumed yet
        @state = 'previewed'
        # NOTE: calling save re-creates all fields so if you're relying on
        # has_field? to be false, it will start returning true after a save.
        save update_expiration: false
      end

      # MIGRATION NOTE: This method replaces the legacy `received!` method.
      # Existing data with state='received' should be migrated to state='revealed'.
      # The `received` timestamp field maps to the new `revealed` field.
      def revealed!
        # A guard to allow only a fresh, new secret to be revealed. Also ensures that
        # we don't support going from :previewed back to something else.
        return unless state?(:new) || state?(:previewed)

        md               = load_receipt
        md.revealed! unless md.nil?
        # It's important for the state to change here, even though we're about to
        # destroy the secret. This is because the state is used to determine if
        # the secret is viewable. If we don't change the state here, the secret
        # will still be viewable b/c (state?(:new) || state?(:previewed) == true).
        @state           = 'revealed'
        # We clear the value, ciphertext, and passphrase_temp immediately so that
        # the secret payload is not recoverable from this instance of the secret;
        # however, we shouldn't clear arbitrary fields here b/c there are valid
        # reasons to be able to call secret.safe_dump for example. This is exactly
        # what happens in Logic::RevealSecret.process which prepares the secret
        # value to be included in the response and then calls this method at the
        # end. It's at that point that `Logic::RevealSecret.success_data` is called
        # which means if we were to clear out say -- state -- it would be null in
        # the API's JSON response. Not a huge deal in that case, but we validate
        # response data in the UI now and this would raise an error.
        @value           = nil
        @ciphertext      = nil  # Clear encrypted field so can_decrypt? returns false
        @passphrase_temp = nil
        destroy!
      end

      def burned!
        # A guard to allow only a fresh, new secret to be burned. Also ensures that
        # we don't support going from :burned back to something else.
        return unless state?(:new) || state?(:previewed)

        md               = load_receipt
        md.burned! unless md.nil?
        @passphrase_temp = nil
        destroy!
      end
    end
  end
end
