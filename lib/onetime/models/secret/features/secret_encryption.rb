# lib/onetime/models/secret/features/secret_encryption.rb

require 'openssl'

module V2::Secret::Features
  module SecretEncryption

    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
      def spawn_pair(custid, token = nil)
        secret   = V2::Secret.create(custid: custid, token: token)
        metadata = V2::Metadata.create(custid: custid, token: token)

        # TODO: Use Familia transaction
        metadata.secret_key = secret.key
        metadata.save

        secret.metadata_key = metadata.key
        secret.save

        [metadata, secret]
      end

      def encryption_key *entropy
        input = entropy.flatten.compact.join ':'
        Digest::SHA256.hexdigest(input) # TODO: Use Familila.generate_id
      end

    end

    module InstanceMethods
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
        v_encrypted.force_encoding('utf-8')

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
          v_decrypted.force_encoding('utf-8') # Hacky fix for https://github.com/onetimesecret/onetimesecret/issues/37
          v_decrypted
        rescue OpenSSL::Cipher::CipherError => ex
          OT.le "[decrypted_value] m:#{metadata_key} s:#{key} CipherError #{ex.message}"
          # Try fallback global secrets for mode 2 (current encryption)
          if encryption_mode == 2 && has_fallback_secrets?
            fallback_result = try_fallback_secrets(v_encrypted, opts)
            return fallback_result if fallback_result
          end

          # If all secrets fail, try nil secret if allowed
          allow_nil = OT.conf['experimental'].fetch('allow_nil_global_secret', false)
          if allow_nil
            OT.li "[decrypted_value] m:#{metadata_key} s:#{key} Trying nil global secret"
            decryption_options = opts.merge(key: encryption_key_v2_with_nil)
            return v_encrypted.decrypt(decryption_options)
          end

          # If nothing works, raise the original error
          raise ex
        end
      end

      # Check if there are additional global secrets configured beyond the primary one
      def has_fallback_secrets?
        rotated_secrets = OT.conf['experimental'].fetch('rotated_secrets', [])
        rotated_secrets.is_a?(Array) && rotated_secrets.length > 1
      end

      # Try to decrypt using each fallback secret
      def try_fallback_secrets(encrypted_value, opts)
        return nil unless has_fallback_secrets?

        rotated_secrets = OT.conf['experimental'].fetch('rotated_secrets', [])
        OT.ld "[try_fallback_secrets] m:#{metadata_key} s:#{key} Trying rotated secrets (#{rotated_secrets.length})"
        rotated_secrets.each_with_index do |fallback_secret, index|
          # Generate key using the fallback secret
          encryption_key = V2::Secret.encryption_key(fallback_secret, key, passphrase_temp)
          result         = encrypted_value.decrypt(opts.merge(key: encryption_key))
          result.force_encoding('utf-8')
          OT.li "[try_fallback_secrets] m:#{metadata_key} s:#{key} Success (index #{index})"
          return result
        rescue OpenSSL::Cipher::CipherError
          # Continue to next secret if this one fails
          OT.ld "[try_fallback_secrets] m:#{metadata_key} s:#{key} Failed (index #{index})"
          next
        end
        nil # Return nil if all fallback secrets fail
      end

      def can_decrypt?
        !value.to_s.empty? && (passphrase.to_s.empty? || !passphrase_temp.to_s.empty?)
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

      def encryption_key_v1 *_ignored
        V2::Secret.encryption_key key, passphrase_temp
      end

      def encryption_key_v2 *_ignored
        V2::Secret.encryption_key OT.global_secret, key, passphrase_temp
      end

      # Used as a failover key when experimental.allow_nil_global_secret is true.
      def encryption_key_v2_with_nil
        V2::Secret.encryption_key nil, key, passphrase_temp
      end

    end

    Familia::Base.add_feature self, :secret_encryption
  end
end
