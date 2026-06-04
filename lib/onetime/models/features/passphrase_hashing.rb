# lib/onetime/models/features/passphrase_hashing.rb
#
# frozen_string_literal: true

require 'argon2'
require 'bcrypt'

module Onetime
  module Models
    module Features
      module PassphraseHashing
        Familia::Base.add_feature self, :passphrase_hashing

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
          base.field :passphrase
          base.field :passphrase_encryption
          base.attr_reader :passphrase_temp
        end

        module InstanceMethods
          def update_passphrase!(val, **)
            update_passphrase(val)
              .save_fields(:passphrase_encryption, :passphrase)
          end

          # Hash a new passphrase using argon2id.
          #
          # @param val [String] The plaintext passphrase to hash
          # @return [self] Enable method chaining
          def update_passphrase(val, **)
            self.passphrase_encryption = '2'
            self.passphrase            = ::Argon2::Password.create(val, argon2_hash_cost)
            self
          end

          def has_passphrase?
            !passphrase.to_s.empty?
          end

          # Verify a passphrase against the stored hash.
          # Supports argon2id (passphrase_encryption='2') and
          # bcrypt (passphrase_encryption='1' or legacy) hashes.
          #
          # @param val [String] The plaintext passphrase to verify
          # @return [Boolean] true if the passphrase matches
          def passphrase?(val)
            return false if passphrase.to_s.empty?

            if argon2_hash?(passphrase)
              ::Argon2::Password.verify_password(val, passphrase)
            else
              BCrypt::Password.new(passphrase) == val
            end
          rescue BCrypt::Errors::InvalidHash => ex
            OT.li "[passphrase?] Invalid BCrypt hash: #{ex.message}"
            false
          rescue ::Argon2::ArgonHashFail => ex
            OT.li "[passphrase?] Argon2 hash operation failed: #{ex.message}"
            false
          end

          def argon2_hash?(hash)
            hash.to_s.start_with?('$argon2id$')
          end

          def argon2_hash_cost
            if ENV['RACK_ENV'] == 'test'
              { t_cost: 1, m_cost: 5, p_cost: 1 }
            else
              { t_cost: 2, m_cost: 16, p_cost: 1 }
            end
          end
        end
      end
    end
  end
end
