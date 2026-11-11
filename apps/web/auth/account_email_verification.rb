# apps/web/auth/account_email_verification.rb
#
# frozen_string_literal: true

module Auth
  # Migration 015's verification columns on `accounts` (ADR-051):
  #
  #   email_verified_at        when mailbox control was established for the
  #                            row's CURRENT address
  #   email_verified_by        how: one of Onetime::Customer::MAILBOX_VERIFIED_BY
  #   email_verification_hold  why an IdP-asserted address was left unverified
  #                            (Onetime::Customer::VERIFICATION_HOLDS)
  #
  # Until the N+1 binary makes SQL the writer, the Customer mirror
  # (`verified`, `verified_by`, `verification_hold`) is what every reader
  # uses, and these columns are derived from it. Every writer derives them
  # here (the backfill, SetCustomerVerification, the after_verify_account
  # hook, ChangeEmail, the doctor's drift repair), so no two of them can map
  # one Customer state to different columns, and `customers doctor`
  # (auth_email_verification_drift) compares against the same mapping.
  #
  # The proof columns record mailbox proof only. `sso`, `stripe_payment`,
  # `autoverify` and `legacy` are not mailbox proof (#4735, #4754), so a
  # Customer verified by one of them leaves the proof columns NULL.
  module AccountEmailVerification
    COLUMNS = [:email_verified_at, :email_verified_by, :email_verification_hold].freeze

    # No proof for the row's address and no hold.
    CLEARED = COLUMNS.to_h { |column| [column, nil] }.freeze

    # The columns for a Customer state, for a row at the Customer's address.
    #
    #   verified with a MAILBOX_VERIFIED_BY provenance -> proof: now, that provenance
    #   otherwise, with a hold                         -> that hold
    #   otherwise                                      -> CLEARED
    #
    # @param verified [Boolean]
    # @param verified_by [String, nil]
    # @param hold [String, nil] the Customer's verification_hold
    # @return [Hash] the three columns
    def self.values(verified:, verified_by:, hold: nil)
      if verified && Onetime::Customer::MAILBOX_VERIFIED_BY.include?(verified_by.to_s)
        return {
          email_verified_at: Sequel::CURRENT_TIMESTAMP,
          email_verified_by: verified_by.to_s,
          email_verification_hold: nil,
        }
      end

      hold = hold.to_s
      hold.empty? ? CLEARED : CLEARED.merge(email_verification_hold: hold)
    end

    # #values for a row whose address may not be the Customer's. Proof and a
    # hold each name a mailbox, so a row at another address gets CLEARED
    # (OT::Utils.same_mailbox?: `straße` and `strasse` are different
    # mailboxes).
    #
    # @return [Hash] the three columns
    def self.values_for_row(row_email, customer_email, **state)
      return CLEARED unless OT::Utils.same_mailbox?(row_email.to_s, customer_email.to_s)

      values(**state)
    end

    # Whether a row's stored columns already say what `wanted` says: proof
    # present or absent, the same provenance, the same hold. The proof time
    # is not compared, so a repeat never moves it.
    #
    # @param row [Hash] the three columns as stored
    # @param wanted [Hash] from #values or #values_for_row
    def self.in_step?(row, wanted)
      row[:email_verified_at].nil? == wanted[:email_verified_at].nil? &&
        row[:email_verified_by].to_s == wanted[:email_verified_by].to_s &&
        row[:email_verification_hold].to_s == wanted[:email_verification_hold].to_s
    end

    # Does this database have the columns (migration 015)? A database
    # without them gets no verification write from any caller.
    #
    # @param db [Sequel::Database]
    def self.columns?(db)
      db.schema(:accounts).any? { |name, _| name == :email_verified_at }
    rescue Sequel::Error
      false
    end
  end
end
