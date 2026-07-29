# lib/onetime/utils/email_format.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # EmailFormat - Basic email format check for model layer
    #
    # Provides format-only checking without DNS/SMTP probes. Use for
    # model-layer where Truemail may not be configured (prior to full
    # application boot).
    #
    # For validation at signup/invitation/share boundaries,
    # use Truemail via Logic::Base#valid_email? instead.
    #
    # For corruption guards in booted contexts, use Truemail :regex mode:
    #   Truemail.validate(email, with: :regex).result.valid?
    #
    module EmailFormat
      # Basic 3-part format check: local@domain.tld
      # Rejects obvious malformations without DNS lookups.
      BASIC_FORMAT = /\A[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/

      # Minimal 3-part shape check (local@domain.tld) with no charset
      # restrictions, so internationalized addresses BASIC_FORMAT would
      # reject still pass. Use where refusing a real-but-unusual address
      # is worse than accepting a malformed one (e.g. suppression-list
      # ingestion, legacy custid recognition).
      MINIMAL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      # Loosest 2-part shape check (local@domain, no TLD required).
      # For heuristics over legacy/unlinked datastore rows where stored
      # addresses may lack a TLD entirely.
      LOOSE_FORMAT = /\A[^@\s]+@[^@\s]+\z/

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
