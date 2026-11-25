# frozen_string_literal: true

module Onetime
  module Logic
    # Length and complexity checks for passphrases supplied by senders.
    module PassphraseValidation
      def validate_provided_passphrase
        # Skip further validation if no passphrase provided
        return if passphrase.to_s.empty?

        # Validate minimum length
        min_length = OT.conf.get('site.secret_options.passphrase.minimum_length', nil)&.to_i
        if min_length && passphrase.length < min_length
          raise_form_error "Passphrase must be at least #{min_length} characters long"
        end

        # Validate maximum length
        max_length = OT.conf.get('site.secret_options.passphrase.maximum_length', nil)
        if max_length && passphrase.length > max_length
          raise_form_error "Passphrase must be no more than #{max_length} characters long"
        end

        # Validate complexity if required
        if OT.conf.get('site.secret_options.passphrase.enforce_complexity', nil)
          validate_passphrase_complexity
        end
      end

      def validate_passphrase_complexity
        errors = []

        # Check for at least one uppercase letter
        errors << 'uppercase letter' unless passphrase.match?(/[A-Z]/)

        # Check for at least one lowercase letter
        errors << 'lowercase letter' unless passphrase.match?(/[a-z]/)

        # Check for at least one number
        errors << 'number' unless passphrase.match?(/\d/)

        # Check for at least one symbol
        errors << 'symbol' unless passphrase.match?(%r{[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?~`]})

        unless errors.empty?
          raise_form_error "Passphrase must contain at least one #{errors.join(', ')}"
        end
      end
    end
  end
end
