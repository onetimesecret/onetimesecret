# lib/onetime/utils/email_format.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # EmailFormat - Basic email format validation for model layer
    #
    # Provides format-only validation without DNS/SMTP probes. Use for
    # model-layer validation where Truemail may not be configured (CLI,
    # console, tests).
    #
    # For user-input validation at signup/invitation/share boundaries,
    # use Truemail via Logic::Base#valid_email? instead.
    #
    # For corruption guards in booted contexts, use Truemail :regex mode:
    #   Truemail.validate(email, with: :regex).result.valid?
    #
    module EmailFormat
      # Basic 3-part format check: local@domain.tld
      # Rejects obvious malformations without DNS lookups.
      BASIC_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      class << self
        # Check basic email format (no DNS, no Truemail dependency)
        #
        # @param email [String] Email address to validate
        # @return [Boolean] True if format matches
        def valid_format?(email)
          BASIC_FORMAT.match?(email.to_s)
        end
      end
    end
  end
end
