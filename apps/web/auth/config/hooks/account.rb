# apps/web/auth/config/hooks/account.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  module Account
    def self.configure(auth)
      #
      # Hook: Before Account Creation
      #
      # This hook is triggered before a new account is created. It performs
      # several validation checks on the provided email address.
      #
      auth.before_create_account do
        # Check if email already exists in either database
        # SECURITY: Two-database consistency check prevents orphaned accounts
        email = param(login_param)

        # Check SQLite (auth database)
        existing_account = db[:accounts].where(email: email).first

        if existing_account
          diagnostic_hint = <<~HINT.strip
            Registration blocked: Account exists in authdb but may be missing from
            Redis. This can occur after clearing Redis without resetting authdb.
            Consider: (1) deleting the account from authdb, or (2) resetting both
            databases together.
          HINT

          Auth::Logging.log_auth_event(
            :registration_blocked_auth_db_conflict,
            level: :error,
            email: OT::Utils.obscure_email(email),
            account_id: existing_account[:id],
            diagnostic_hint: diagnostic_hint,
          )

          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
        end

        # Check Redis (customer database)
        # Note: In shared Redis dev setups, a customer may exist without an auth account
        if Onetime::Customer.email_exists?(email)
          diagnostic_hint = <<~HINT.strip
            Registration blocked: Customer record exists in Redis but no auth account
            found. This typically occurs in worktree/multi-instance dev setups with
            shared Redis. Consider: (1) using isolated Redis per instance, (2) clearing
            Redis data, or (3) logging in with existing account if it exists elsewhere.
          HINT

          Auth::Logging.log_auth_event(
            :registration_blocked_redis_conflict,
            level: :error,
            email: OT::Utils.obscure_email(email),
            diagnostic_hint: diagnostic_hint,
          )

          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
        end
      end

      # When this is part of a regular user signup flow, we'll have already
      # called Truemail.validate on this address in the CreateAccount logic,
      # but we call it here as a defensive in depth regardless. It's easier
      # to call it twice than to try to keep track of the state through
      # multiple codepaths.
      auth.login_valid_email? do |email|
        validator = Truemail.validate(email)
        is_valid  = super(email) && validator.result.valid?

        unless is_valid
          Auth::Logging.log_auth_event(
            :invalid_email_rejected,
            level: :info,
            email: email,
          )
        end

        is_valid
      end

      #
      # Hook: After Account Creation
      #
      # This hook is triggered after a new user successfully creates an account.
      # It ensures a corresponding Onetime::Customer record is created and linked,
      # and creates a default organization and team for the new user.
      #
      auth.after_create_account do
        customer = Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: Auth::Database.connection,
          ).call
        end

        # Create default organization and team for the new customer
        # Note: These are hidden from individual plan users in the UI
        if customer.is_a?(Onetime::Customer)
          Onetime::ErrorHandler.safe_execute('create_default_workspace', extid: customer.extid) do
            Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
          end

          # Capture plan intent for email verification flow (issue #3126)
          # Session-based billing redirect doesn't survive email verification, so we
          # persist the plan selection on the Customer record with a 24h TTL.
          product  = request.params['product']
          interval = request.params['interval']

          if product.to_s.strip != '' && interval.to_s.strip != ''
            intent = {
              product: product,
              interval: interval,
              captured_at: Time.now.utc.iso8601,
              source_url: request.fullpath,
            }.to_json

            customer.pending_plan_intent = intent

            Auth::Logging.log_auth_event(
              :plan_intent_captured,
              level: :debug,
              customer_extid: customer.extid,
              product: product,
              interval: interval,
            )
          end

          # Accept pending invitation if token provided in signup request
          invite_token = request.params['invite_token']
          if invite_token && !invite_token.to_s.strip.empty?
            Auth::Logging.log_auth_event(
              :invite_acceptance_started,
              level: :debug,
              email: customer.email,
              account_id: account_id,
              invite_token_prefix: invite_token.to_s[0..7],
            )

            Onetime::ErrorHandler.safe_execute('accept_invitation', token: invite_token) do
              result = Auth::Operations::AcceptInvitation.new(
                customer: customer,
                token: invite_token,
              ).call

              if result[:accepted]
                # Auto-verify at SQL level — invite link proves email ownership
                update_account(account_status_column => account_open_status_value)
                # Remove verification key — clean up the key row
                had_verify_key = respond_to?(:remove_verify_account_key)
                remove_verify_account_key if had_verify_key

                # Signal to create_account_autologin? that this signup has a verified invite.
                # Set AFTER DB operations so autologin only fires if verification succeeded.
                @invite_accepted = true

                Auth::Logging.log_auth_event(
                  :invitation_accepted,
                  level: :info,
                  email: customer.email,
                  account_id: account_id,
                  organization_id: result[:organization_id],
                  role: result[:role],
                  account_auto_verified: true,
                  verify_key_removed: had_verify_key,
                  autologin_flag_set: true,
                )
              else
                Auth::Logging.log_auth_event(
                  :invitation_not_accepted,
                  level: :warn,
                  email: customer.email,
                  account_id: account_id,
                  reason: result[:reason],
                  invite_token_prefix: invite_token.to_s[0..7],
                )
              end
            end
          end
        end
      end

      #
      # Hook: After Account Verification
      #
      # This hook is triggered when a user verifies their account (e.g., by
      # clicking a link in an email). It updates the verification status of
      # the associated Onetime::Customer record.
      #
      # Note: This hook is disabled in the 'test' environment to simplify
      # testing scenarios that do not require email verification flows.
      #
      unless Onetime.env?('testing')
        auth.after_verify_account do
          Auth::Logging.log_auth_event(
            :account_verified,
            level: :info,
            account_id: account_id,
            external_id: account[:external_id],
            email: account[:email],
          )

          Onetime::ErrorHandler.safe_execute('verify_customer', extid: account[:external_id]) do
            next unless account[:external_id]

            customer = Onetime::Customer.find_by_extid(account[:external_id])
            next unless customer

            Auth::Operations::SetCustomerVerification.new(
              customer: customer,
              verified: true,
              verified_by: 'email',
              rodauth_already_synced: true,
            ).call
          end

          # Surface pending plan intent for checkout redirect (issue #3126)
          # If the user had selected a plan before signup, redirect them to checkout
          # after verification completes.
          Onetime::ErrorHandler.safe_execute('surface_plan_intent', extid: account[:extid]) do
            # account[:external_id] (Rodauth/SQL) == customer.extid (Familia/Redis)
            customer = Onetime::Customer.find_by_extid(account[:external_id])

            if customer&.pending_plan_intent&.value.to_s.strip != ''
              begin
                intent   = JSON.parse(customer.pending_plan_intent.value)
                product  = intent['product']
                interval = intent['interval']

                # Lazy-load billing dependencies (may not be available on self-hosted)
                require_relative '../../../billing/lib/plan_resolver'

                # Validate the plan still exists before redirecting
                result = ::Billing::PlanResolver.resolve(product: product, interval: interval)

                if result.success?
                  customer.pending_plan_intent.delete!

                  # Store redirect in session for verify_account_redirect
                  enc_product                       = URI.encode_www_form_component(product)
                  enc_interval                      = URI.encode_www_form_component(interval)
                  session['plan_checkout_redirect'] = "/billing/plans/#{enc_product}/#{enc_interval}"

                  Auth::Logging.log_auth_event(
                    :plan_intent_surfaced,
                    level: :info,
                    customer_extid: customer.extid,
                    product: product,
                    interval: interval,
                  )
                else
                  customer.pending_plan_intent.delete!

                  Auth::Logging.log_auth_event(
                    :plan_intent_invalid,
                    level: :warn,
                    customer_extid: customer.extid,
                    product: product,
                    interval: interval,
                    error: result.error,
                  )
                end
              rescue JSON::ParserError => ex
                customer.pending_plan_intent.delete!

                Auth::Logging.log_auth_event(
                  :plan_intent_parse_error,
                  level: :warn,
                  customer_extid: customer.extid,
                  error: ex.message,
                )
              rescue LoadError
                customer.pending_plan_intent.delete!
              end
            end
          end
        end
      end

      #
      # Hook: After Password Reset Request
      #
      # This hook is triggered after a user requests a password reset.
      #
      auth.after_reset_password_request do
        Auth::Logging.log_auth_event(
          :password_reset_requested,
          level: :info,
          account_id: account_id,
          email: account[:email],
        )
      end

      #
      # Hook: After Password Reset
      #
      # This hook is triggered after a user successfully resets their password.
      #
      auth.after_reset_password do
        Auth::Logging.log_auth_event(
          :password_reset_complete,
          level: :info,
          account_id: account_id,
          email: account[:email],
        )
      end

      #
      # Hook: After Password Change
      #
      # This hook is triggered after a user changes their password. It updates
      # metadata in the associated Onetime::Customer record.
      #
      auth.after_change_password do
        Auth::Logging.log_auth_event(
          :password_changed,
          level: :info,
          account_id: account_id,
          email: account[:email],
        )

        # Rodauth is the source of truth for password management. Here, we just
        # sync metadata to the customer record.
        Onetime::ErrorHandler.safe_execute('update_password_metadata', email: account[:email]) do
          Auth::Operations::UpdatePasswordMetadata.new(account: account).call
        end
      end

      #
      # Hook: After Account Closure
      #
      # This hook is triggered when a user closes their account. It handles the
      # cleanup of the associated Onetime::Customer record.
      #
      auth.after_close_account do
        Auth::Logging.log_auth_event(
          :account_closed,
          level: :info,
          account_id: account_id,
          external_id: account[:external_id],
          email: account[:email],
        )

        Onetime::ErrorHandler.safe_execute('delete_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::DeleteCustomer.new(account: account).call
        end
      end
    end
  end
end
