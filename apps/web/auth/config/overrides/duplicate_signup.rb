# apps/web/auth/config/overrides/duplicate_signup.rb
#
# frozen_string_literal: true

#
# One answer for a sign-up whose login already has an account.
#
# MECHANISM: method overrides via `auth_class_eval` (see config/overrides.rb).
#
# WHY THIS EXISTS
# ---------------
# POST /auth/create-account decides "this login is taken" in three places:
#
#   1. verify_account's `new_account`, before the transaction: an UNVERIFIED
#      account. Stock Rodauth answers 403 (`unopen_account_error_status`)
#      where a verified account answers 400, so the status alone told a
#      caller which of the two states the account was in.
#   2. `before_create_account` (config/hooks/account.rb), inside the
#      transaction: an account in the authdb answers 400 with the same error.
#   3. `save_account`, at the INSERT: a unique violation. Stock Rodauth
#      answers 422 with a `field-error` naming the login and the reason
#      "already an account with this login".
#
# (1) and (2) are the ordinary duplicate. (3) is only reachable by a request
# that passed (1) and (2) while another sign-up for the same login was
# between its own checks and its commit: a race. Its answer differed from the
# ordinary one in status and in body, and said in words what the generic
# error exists not to say.
#
# All three now give ONE answer: 400 with the generic create-account error.
# `new_account` is overridden so an unverified account answers like a verified
# one (the original flash reader still runs, so the `create_account_blocked`
# log line is kept), and both late detections answer through
# {#refuse_signup_for_existing_account}. A request that loses the race is
# therefore indistinguishable from one that arrived a moment later, and an
# unverified account from a verified one, on SQLite (where the
# transaction serializes the two and the loser is caught by (2)) and on
# PostgreSQL (where both reach the INSERT and the loser is caught by (3)).
#
# The INSERT runs in a savepoint (Rodauth's raises_uniqueness_violation?), so
# on PostgreSQL the transaction is still usable for the lookup after it.
#
module Auth::Config::Overrides
  module DuplicateSignup
    def self.configure(auth)
      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # Answer a sign-up for a login that already has an account, the way
        # an ordinary duplicate is answered. Always halts.
        def refuse_signup_for_existing_account(_login)
          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
        end

        # An unverified account answers a sign-up the way a verified one
        # does. verify_account's version answers 403 and renders the resend
        # view; the status was the only difference a JSON caller could see,
        # and it named the account's state. The route calls this OUTSIDE its
        # catch_error block, so it returns the response itself instead of
        # throwing; with no status set here, the JSON layer supplies the same
        # default the thrown error gets. The unverified flash reader is still
        # called for its `create_account_blocked` log line.
        def new_account(login)
          if features.include?(:verify_account) && account_from_login(login) && allow_resending_verify_account_email?
            attempt_to_create_unverified_account_error_flash
            set_error_flash(create_account_error_flash)
            request.env['rodauth.error_flash'] = create_account_error_flash
            return_response create_account_view
          end
          super
        end

        def save_account
          saved = super
          return saved if saved

          login = account[login_column]
          return saved if db[accounts_table].where(login_column => login).empty?

          Auth::Logging.log_auth_event(
            :registration_lost_signup_race,
            level: :info,
            email: OT::Utils.obscure_email(login),
          )
          refuse_signup_for_existing_account(login)
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
