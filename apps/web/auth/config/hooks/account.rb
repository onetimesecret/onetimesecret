# apps/web/auth/config/hooks/account.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  module Account
    # rubocop:disable Metrics/PerceivedComplexity
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

        # Per-domain signup validation (allowlist, MX, SMTP).
        # Resolves the CustomDomain by display_domain and enforces its
        # SignupConfig if one is configured and enabled. Falls back to the
        # global allowed_signup_domains policy when no per-domain config
        # applies. Identical user-visible error message to the existing
        # email-conflict paths prevents enumeration of which domains, MX
        # records, or mailboxes are accepted.
        display_domain = request.env['onetime.display_domain']
        unless Onetime::SignupValidation.valid_signup_email?(email, display_domain: display_domain)
          Auth::Logging.log_auth_event(
            :registration_blocked_signup_validation,
            level: :info,
            email: OT::Utils.obscure_email(email),
            display_domain: display_domain,
          )

          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
        end

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

        # When an invite_token is supplied, validate the invitation up front:
        # invitation exists, still pending, not expired, and the signup email
        # matches the invited email. Failing precondition checks here aborts
        # before any account/customer row is written, so we never roll back
        # partial Redis state on email-mismatch or expired tokens.
        invite_token = param_or_nil('invite_token').to_s.strip
        unless invite_token.empty?
          invitation = Onetime::OrganizationMembership.find_by_token(invite_token)

          invalid_reason =
            if invitation.nil?
              'token_not_found'
            elsif !invitation.pending?
              'not_pending'
            elsif invitation.expired?
              'expired'
            elsif OT::Utils.normalize_email(email) !=
                  OT::Utils.normalize_email(invitation.invited_email)
              'email_mismatch'
            end

          if invalid_reason
            Auth::Logging.log_auth_event(
              :registration_blocked_invalid_invite,
              level: :warn,
              email: OT::Utils.obscure_email(email),
              invite_token_prefix: invite_token[0..7],
              reason: invalid_reason,
            )

            set_error_flash(create_account_error_flash)
            request.env['rodauth.error_flash'] = create_account_error_flash
            throw_rodauth_error
          end
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
        # Read via Rodauth's `param_or_nil` so this hook works under both
        # normal HTTP requests and `internal_request` (which only populates
        # rodauth.params, not the Rack request body).
        hook_invite_token = param_or_nil('invite_token').to_s.strip

        # Determine the provisioning origin from request context. This is
        # metadata only — capabilities are governed by org/team role.
        provisioning_origin = if hook_invite_token != ''
                                'invite'
                              elsif request.env['onetime.display_domain'] &&
                                    Onetime::CustomDomain.load_by_display_domain(request.env['onetime.display_domain'])
                                'domain_signup'
                              else
                                'canonical_signup'
                              end

        customer = Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: Auth::Database.connection,
            provisioning_origin: provisioning_origin,
          ).call
        end

        if customer.is_a?(Onetime::Customer)
          invite_token  = hook_invite_token
          invite_signup = !invite_token.empty?

          if invite_signup
            # Invite signup: skip default workspace creation. The user is joining
            # an existing org via the explicit POST /api/invite/:token/accept
            # call that follows signup. A personal default workspace would be
            # dead state they never use.
            #
            # Auto-verify at both the Redis (customer) and SQL (account) layers.
            # The invite link itself proves email ownership — before_create_account
            # already validated the token and that the signup email matches the
            # invited email, so we can mark the customer verified here without
            # a separate email round-trip.
            Onetime::ErrorHandler.safe_execute('auto_verify_invite_signup', extid: customer.extid) do
              customer.verified    = true
              customer.verified_by = 'invite_token'
              customer.save

              update_account(account_status_column => account_open_status_value)

              had_verify_key = respond_to?(:remove_verify_account_key)
              remove_verify_account_key if had_verify_key

              # Signal to create_account_autologin? that this is an invite signup.
              # The user gets a session immediately so the frontend can POST to
              # /api/invite/:token/accept with the active cookie. The token is
              # NOT consumed here — that's the point of the explicit accept step.
              @invite_accepted = true

              Auth::Logging.log_auth_event(
                :invite_signup_verified,
                level: :info,
                email: customer.email,
                account_id: account_id,
                invite_token_prefix: invite_token[0..7],
                verify_key_removed: had_verify_key,
                autologin_flag_set: true,
              )
            end
          else
            # Standard signup: provision the default organization and team so
            # the user has a workspace to land in after email verification.
            Onetime::ErrorHandler.safe_execute('create_default_workspace', extid: customer.extid) do
              Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
            end
          end

          # Capture plan intent for email verification flow (issue #3126).
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
        end
      end

      #
      # Hook: After Account Verification
      #
      # This hook is triggered when a user verifies their account (e.g., by
      # clicking a link in an email). It updates the verification status of
      # the associated Onetime::Customer record.
      #
      # This hook is only registered when the verify_account feature is enabled.
      # When disabled (e.g., in test environments via auth.yaml config), the
      # Rodauth :verify_account feature isn't loaded, so the after_verify_account
      # DSL method doesn't exist.
      #
      if Onetime.auth_config.verify_account_enabled?
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
    # rubocop:enable Metrics/PerceivedComplexity
  end
end
