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
#      account answers 403 with the generic create-account error.
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
# Both late detections now answer through {#refuse_signup_for_existing_account},
# which replays the ordinary decision against the account that exists NOW:
# `new_account` answers 403 when that account is unverified, and anything else
# gets the hook's generic 400. A request that loses the race is therefore
# indistinguishable from one that arrived a moment later, on SQLite (where the
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
        def refuse_signup_for_existing_account(login)
          # verify_account: halts here with 403 when the account is unverified.
          new_account(login)

          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
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
