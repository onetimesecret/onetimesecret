# apps/web/auth/account_statuses.rb
#
# frozen_string_literal: true

module Auth
  # Rodauth account status ids — the single code-side mirror of the
  # account_statuses reference table seeded in migrations/001_initial.rb.
  #
  # LIVE matters beyond readability: the unique index on accounts.email is
  # PARTIAL (`where status_id in (1, 2)`), so only LIVE rows are covered by
  # email uniqueness. A Closed row can share a live row's address, which is
  # why email-keyed queries must constrain on these ids (#3916).
  module AccountStatuses
    UNVERIFIED = 1
    VERIFIED   = 2
    CLOSED     = 3

    # Statuses covered by the partial unique index on accounts.email.
    LIVE = [UNVERIFIED, VERIFIED].freeze
  end
end
