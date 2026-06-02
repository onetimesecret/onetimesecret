# lib/onetime/models/features/legacy_encrypted_fields.rb
#
# frozen_string_literal: true

require 'argon2'

module Onetime
  module Models
    module Features
      module LegacyEncryptedFields
        Familia::Base.add_feature self, :legacy_encrypted_fields

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods
          base.field :passphrase
          base.field :passphrase_encryption
          base.field :value
          base.field :value_encryption
          base.attr_reader :passphrase_temp
        end

        module ClassMethods
          # DEPRECATED: Use Onetime::Receipt.spawn_pair instead.
          #
          # This method stores the custid parameter in the `custid` field, which
          # historically contained email addresses (PII). New code should use
          # Receipt.spawn_pair which stores the owner's objid in `owner_id`.
          #
          # @param custid [String] Customer identifier (historically email, now objid)
          # @return [Array<Receipt, Secret>] The linked receipt/secret pair
          # @deprecated Use {Onetime::Receipt.spawn_pair} with objid instead
          #
          def legacy_spawn_pair(custid)
            OT.info '[DEPRECATED] legacy_spawn_pair called - use Receipt.spawn_pair with objid instead'

            secret  = Onetime::Secret.create!
            receipt = Onetime::Receipt.create!(custid: custid)

            # TODO: Use Familia transaction
            receipt.secret_identifier = secret.identifier
            receipt.save

            secret.receipt_identifier = receipt.identifier
            secret.save

            [receipt, secret]
          end

          def encryption_key(*entropy)
            input = entropy.flatten.compact.join ':'
            Digest::SHA256.hexdigest(input) # TODO: Use Familila.generate_id
          end
        end

        module InstanceMethods
          def encryption_key
            Onetime::Secret.encryption_key OT.global_secret, identifier
          end

          def encrypt_value(original_value, opts = {})
            # Handles empty values with a special encryption flag. This is important
            # for consistency in how we deal with these values and expressly for Ruby
            # 3.1 which uses an older version of openssl that does not tolerate empty
            # strings like the more progressive 3.2+ Rubies.
            if original_value.to_s.empty?
              self.value_encryption = -1
              return
            end

            # Determine if the secret exceeds the configured size threshold
            if opts[:size] && original_value.length >= opts[:size]
              # Apply randomized truncation to mitigate information leakage. By
              # varying the actual truncation point by 0-20%, we prevent attackers
              # from inferring the exact content length, which could leak information
              # about the secret's contents.
              random_factor = 1.0 + (rand * 0.2) # Random factor between 1.0-1.2
              adjusted_size = (opts[:size] * random_factor).to_i

              # The random factor already ensures fuzziness up to 20% above base
              # size. This ensures unpredictable truncation points within a
              # controlled range.
              storable_value = original_value.slice(0, adjusted_size)
              self.truncated = true
            else
              storable_value = original_value
            end
            # Secure the value with cryptographic encryption
            self.value_encryption = 2 # Current encryption version

            encryption_options = opts.merge(key: encryption_key)
            self.value         = storable_value.encrypt encryption_options
          end

          def decrypted_value(opts = {})
            encryption_mode = value_encryption.to_i
            v_encrypted     = value
            v_encrypted     = '' if encryption_mode.negative? && v_encrypted.nil?
            v_encrypted     = v_encrypted.dup.force_encoding('utf-8')

            # First try with the primary global secret
            begin
              v_decrypted = case encryption_mode
                            when -1
                              ''
                            when 0
                              v_encrypted
                            when 1
                              v_encrypted.decrypt opts.merge(key: encryption_key_v1)
                            when 2
                              v_encrypted.decrypt opts.merge(key: encryption_key_v2)
                            else
                              raise "Unknown encryption mode: #{value_encryption}"
                            end
              v_decrypted.dup.force_encoding('utf-8') # Hacky fix for https://github.com/onetimesecret/onetimesecret/issues/37
            rescue OpenSSL::Cipher::CipherError => ex
              OT.le "[decrypted_value] r:#{receipt_identifier} s:#{identifier} CipherError #{ex.message}"

              # Try nil secret if allowed (development mode only) and current global
              # secret is nil. When global_secret is non-nil, a CipherError means
              # the passphrase is wrong — not a nil-secret migration scenario.
              allow_nil = OT.conf['development'].fetch('allow_nil_global_secret', false)
              if allow_nil && OT.global_secret.nil?
                OT.li "[decrypted_value] r:#{receipt_identifier} s:#{identifier} Trying nil global secret"
                decryption_options = opts.merge(key: encryption_key_v2_with_nil)
                return v_encrypted.decrypt(decryption_options)
              end

              # If nothing works, raise the original error
              raise ex
            end
          end

          def can_decrypt?
            (!ciphertext.to_s.empty? || !value.to_s.empty?) && (passphrase.to_s.empty? || !passphrase_temp.to_s.empty?)
          end

          def encryption_key(*)
            case value_encryption.to_i
            when 0
              value
            when 1 # Last used 2012-01-07
              encryption_key_v1(*)
            when 2
              encryption_key_v2(*)
            else
              raise "Unknown encryption mode: #{value_encryption}"
            end
          end

          def encryption_key_v1(*_ignored)
            Onetime::Secret.encryption_key identifier, passphrase_temp
          end

          def encryption_key_v2(*_ignored)
            Onetime::Secret.encryption_key OT.global_secret, identifier, passphrase_temp
          end

          # Used as a failover key when development.allow_nil_global_secret is true.
          def encryption_key_v2_with_nil
            Onetime::Secret.encryption_key nil, identifier, passphrase_temp
          end

          def update_passphrase!(val, algorithm: :argon2)
            update_passphrase(val, algorithm: algorithm)
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

          # Verify a passphrase against the stored argon2id hash.
          #
          # @param val [String] The plaintext passphrase to verify
          # @return [Boolean] true if the passphrase matches
          def passphrase?(val)
            return false if passphrase.to_s.empty?

            ::Argon2::Password.verify_password(val, passphrase)
          rescue ::Argon2::ArgonHashFail => ex
            OT.li "[passphrase?] Argon2 hash operation failed: #{ex.message}"
            false
          end

          # Check if a hash string is an argon2id hash.
          #
          # @param hash [String] The hash to check
          # @return [Boolean] true if the hash is argon2id format
          def argon2_hash?(hash)
            hash.to_s.start_with?('$argon2id$')
          end

          # Returns the argon2 hash cost parameters.
          # Uses lower cost in test environment for faster test execution.
          #
          # @return [Hash] Cost parameters for Argon2::Password.create
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
