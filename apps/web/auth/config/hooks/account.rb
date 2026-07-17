# apps/web/auth/config/hooks/account.rb
#
# frozen_string_literal: true

# Redis-only, except-current session revoke used by the password hooks below to
# enforce M-2 (sessions must not survive a password change/reset). Required
# explicitly (mirroring the colonel logic classes) so the constant is loaded when
# these hooks fire, rather than relying on ambient load order.
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'

module Auth::Config::Hooks
  module Account
    # rubocop:disable Metrics/PerceivedComplexity, Metrics/MethodLength
    def self.configure(auth)
      #
      # Hook: Before Account Creation
      #
      # This hook is triggered before a new account is created. It performs
      # several validation checks on the provided email address.
      #
      # NOTE: Rodauth hooks don't chain — each auth.before_create_account call
      # overwrites the previous definition. All before_create_account logic must
      # live here, not split across hook files. billing.rb's capture_plan_selection
      # was moved here after the hook-collision bug (#3275).
      #
      auth.before_create_account do
        # Billing: capture plan selection from query params before validation.
        # Method defined by Billing.configure via auth_class_eval; no-op if billing disabled.
        capture_plan_selection if respond_to?(:capture_plan_selection)

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
            #
            # SECURITY: a standard email/password account is NOT email-verified
            # at this point (the verification email hasn't even been sent). Defer
            # claiming any PendingFederatedSubscription until the user verifies,
            # so an attacker cannot register a paying subscriber's email in this
            # region and steal their federated subscription at signup time. The
            # deferred claim runs from after_verify_account below.
            #
            # When verify_account is disabled for this deployment there is no
            # verification step to defer to, so we preserve the immediate-claim
            # behavior (require_verification: false) rather than never claiming.
            #
            # RESIDUAL: in that verify-disabled config the immediate claim
            # happens with NO proof of email ownership — an attacker who knows a
            # subscriber's email could register it here and claim their pending
            # federated subscription. We deliberately do not gate on verified?
            # here (the Redis customer.verified flag never becomes true without
            # verify_account, so gating would disable federated claims entirely);
            # CreateDefaultWorkspace instead emits a loud security-audit log for
            # each such unverified immediate claim. See
            # CreateDefaultWorkspace#apply_pending_federation! and #initialize.
            require_verification = Onetime.auth_config.verify_account_enabled?

            Onetime::ErrorHandler.safe_execute('create_default_workspace', extid: customer.extid) do
              Auth::Operations::CreateDefaultWorkspace.new(
                customer: customer,
                require_verification: require_verification,
              ).call
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

        # Billing redirect: add plan selection to JSON response (issue #3275).
        # Billing.configure defines add_billing_redirect_to_response via auth_class_eval,
        # so the method is only available when billing is enabled. Check respond_to?
        # to avoid NoMethodError when billing is disabled (self-hosted).
        if json_request? && respond_to?(:add_billing_redirect_to_response)
          add_billing_redirect_to_response
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

          # Claim any pending federated subscription now that the email is
          # verified (issue: federated benefit theft via unverified signup).
          # CreateDefaultWorkspace defers this claim on the standard signup path;
          # here we apply it to the workspace created at signup. Idempotent and a
          # safe no-op when nothing is pending or it was already claimed. Re-fetch
          # the customer so verified? reflects the state just persisted above.
          Onetime::ErrorHandler.safe_execute('claim_pending_federation', extid: account[:external_id]) do
            next unless account[:external_id]

            verified_customer = Onetime::Customer.find_by_extid(account[:external_id])
            next unless verified_customer

            Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(verified_customer)
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

        # SECURITY (M-2): a password reset MUST invalidate every existing session
        # for the account — the whole point of a reset is to lock out whoever
        # currently holds a live session. The user is UNAUTHENTICATED here (they
        # followed an email link), so there is no current session to preserve:
        # revoke them ALL.
        #
        # Rodauth's own clear_tokens(:reset_password) already ran inside this
        # transaction and cleared the SQL account_active_session_keys rows (full
        # mode). But those rows only gate /auth/* routes; the app's real auth gate
        # is the encrypted Redis session blob (BaseSessionAuthStrategy). Revoke
        # those blobs here or a pre-reset attacker session survives the reset.
        # Deliberately NOT wrapped in Onetime::ErrorHandler.safe_execute. That
        # helper swallows a StandardError into a routine :warn-level "error-handler"
        # log line and returns nil — so a Redis DELETE that raises here would leave
        # the pre-reset session blobs ALIVE while the reset still reports success.
        # That is fail-OPEN for the exact scenario a reset exists to defend against
        # (a stolen session surviving the credential change). We handle the raise
        # EXPLICITLY below: distinct error-level event + Sentry re-capture, so a
        # non-revoking reset pages instead of blending into routine hook logging.
        #
        # ACCEPTED RESIDUAL RISK: revocation here is best-effort, not guaranteed.
        # A durable idempotent retry (enqueue RevokeAllForCustomerExceptCurrent on
        # failure) is the tracked follow-up; the operation is already idempotent so
        # a retry is safe. Until then a Redis-raise leaves blobs live but LOUDLY.
        #
        # Fail SECURE (M-2): revocation MUST still run when external_id is absent.
        # A bare `next unless account[:external_id]` would silently skip the revoke
        # and leave live session blobs alive across the reset. Fall back to the
        # account email — RevokeAllForCustomerExceptCurrent resolves it the same way
        # (Customer.load_by_extid_or_email). Only when neither identifier is usable
        # do we skip, and then LOUDLY so a non-revoking reset is visible.
        custid = account[:external_id].to_s.empty? ? account[:email] : account[:external_id]
        if custid.to_s.strip.empty?
          Auth::Logging.log_auth_event(
            :sessions_revoke_skipped_no_identity,
            level: :warn,
            account_id: account_id,
          )
        else
          begin
            # scan_untracked: false keeps the bounded keyspace SCAN out of Rodauth's
            # open reset transaction; the guaranteed tracked kill still revokes every
            # post-sidecar session (see RevokeAllForCustomerExceptCurrent docs).
            result = Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
              custid: custid,
              scan_untracked: false,
            ).call

            Auth::Logging.log_auth_event(
              :sessions_revoked_on_reset,
              level: :info,
              account_id: account_id,
              blobs_deleted: result.blobs_deleted,
              scan_capped: result.scan_capped,
            )
          rescue StandardError => ex
            # FAIL-OPEN, MADE LOUD: the reset already committed (Rodauth cleared the
            # SQL reset tokens), but the encrypted Redis session blobs may STILL be
            # live. Emit a distinct error-level event and re-capture to Sentry so
            # this alerts rather than hiding in routine error-handler logging.
            Auth::Logging.log_auth_event(
              :sessions_revoke_FAILED,
              level: :error,
              account_id: account_id,
              hook: :after_reset_password,
              error: ex.message,
              security_warning: 'password reset succeeded but pre-reset session blobs may still be live',
            )

            if defined?(Sentry) && Sentry.initialized?
              Sentry.capture_exception(ex) do |scope|
                scope.set_level(:error)
                scope.set_tags(component: 'auth.session_revocation', hook: 'after_reset_password', finding: 'M-2')
                scope.set_context('session_revocation', { account_id: account_id })
              end
            end
          end
        end
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

        # SECURITY (M-2): changing the password must sign out every OTHER session
        # (the standard "someone may know my password" remediation) while KEEPING
        # the session the user is changing it from. Unlike reset, change_password
        # does NOT trigger Rodauth's clear_tokens, so BOTH session stores must be
        # handled here.
        #
        # Resolve the current Rack session id (== the sid tracked in
        # Customer#active_sessions). If it cannot be determined we fail SECURE:
        # except_session_id stays nil, revoking ALL sessions incl. the current one,
        # so the user is simply logged out rather than a stale session surviving.
        current_sid = begin
          session.id&.public_id
        rescue StandardError => ex
          # Item 6: surface the swallowed error so a failure to resolve the
          # current sid is visible. We still fall through to nil (fail SECURE:
          # except_session_id stays nil → the user is logged out of every
          # session incl. the current one, rather than a stale one surviving).
          Auth::Logging.log_auth_event(
            :current_session_id_unresolved,
            level: :warn,
            account_id: account_id,
            error: ex.message,
          )
          nil
        end

        # (1) Rodauth SQL account_active_session_keys (full mode only; the
        # active_sessions feature is toggleable via AUTH_ACTIVE_SESSIONS_ENABLED and
        # absent in simple mode, so guard on respond_to?). Keeps the current Rodauth
        # session key. The user is logged in here, so the helper's except-current
        # path applies.
        if respond_to?(:remove_all_active_sessions_except_current)
          Onetime::ErrorHandler.safe_execute('revoke_rodauth_sessions_on_change', account_id: account_id) do
            remove_all_active_sessions_except_current
          end
        end

        # (2) Encrypted Redis session blobs — the real app auth gate
        # (BaseSessionAuthStrategy). Keep the current sid; revoke the rest.
        #
        # Deliberately NOT wrapped in Onetime::ErrorHandler.safe_execute (same
        # reasoning as after_reset_password above): that helper would swallow a
        # Redis-raise into routine :warn error-handler logging and return nil, so a
        # failed DELETE leaves the OTHER session blobs ALIVE while the change still
        # reports success — fail-OPEN for the "someone may know my password"
        # remediation. We handle the raise EXPLICITLY: distinct error-level event +
        # Sentry re-capture so a non-revoking change alerts.
        #
        # ACCEPTED RESIDUAL RISK: revocation here is best-effort, not guaranteed; a
        # durable idempotent retry is the tracked follow-up (op is idempotent).
        #
        # Fail SECURE (M-2): revocation MUST still run when external_id is absent.
        # A bare `next unless account[:external_id]` would silently skip the revoke
        # and leave OTHER live session blobs alive across the change. Fall back to
        # the account email — RevokeAllForCustomerExceptCurrent resolves it the same
        # way (Customer.load_by_extid_or_email). Only when neither identifier is
        # usable do we skip, and then LOUDLY so a non-revoking change is visible.
        custid = account[:external_id].to_s.empty? ? account[:email] : account[:external_id]
        if custid.to_s.strip.empty?
          Auth::Logging.log_auth_event(
            :sessions_revoke_skipped_no_identity,
            level: :warn,
            account_id: account_id,
          )
        else
          begin
            # scan_untracked: false keeps the bounded keyspace SCAN out of Rodauth's
            # open change transaction; the guaranteed tracked kill still revokes every
            # OTHER post-sidecar session (see RevokeAllForCustomerExceptCurrent docs).
            result = Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
              custid: custid,
              except_session_id: current_sid,
              scan_untracked: false,
            ).call

            Auth::Logging.log_auth_event(
              :sessions_revoked_on_change,
              level: :info,
              account_id: account_id,
              blobs_deleted: result.blobs_deleted,
              kept_current: !current_sid.to_s.empty?,
              scan_capped: result.scan_capped,
            )
          rescue StandardError => ex
            # FAIL-OPEN, MADE LOUD: the password change already committed, but the
            # OTHER encrypted Redis session blobs may STILL be live. Emit a distinct
            # error-level event and re-capture to Sentry so this alerts rather than
            # hiding in routine error-handler logging.
            Auth::Logging.log_auth_event(
              :sessions_revoke_FAILED,
              level: :error,
              account_id: account_id,
              hook: :after_change_password,
              error: ex.message,
              security_warning: 'password change succeeded but other session blobs may still be live',
            )

            if defined?(Sentry) && Sentry.initialized?
              Sentry.capture_exception(ex) do |scope|
                scope.set_level(:error)
                scope.set_tags(component: 'auth.session_revocation', hook: 'after_change_password', finding: 'M-2')
                scope.set_context('session_revocation', { account_id: account_id })
              end
            end
          end
        end

        # Best-effort security notification that the password changed. Never
        # let a delivery problem surface as a password-change failure.
        Onetime::ErrorHandler.safe_execute('password_changed_email', account_id: account_id) do
          recipient = Onetime::Customer.find_by_email(account[:email])
          Onetime::Jobs::Publisher.enqueue_email(
            :password_changed,
            {
              email_address: account[:email],
              changed_at: Time.now.utc.iso8601,
              locale: recipient&.locale || OT.default_locale,
            },
            fallback: :async_thread,
          )
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
    # rubocop:enable Metrics/PerceivedComplexity, Metrics/MethodLength
  end
end
