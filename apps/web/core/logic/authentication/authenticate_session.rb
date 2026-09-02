# apps/web/core/logic/authentication/authenticate_session.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'
require 'onetime/colonel_signin_failure'
require 'onetime/models/colonel_audit_event'
require 'onetime/security/login_rate_limiter'

module Core::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class AuthenticateSession < Onetime::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Security::LoginRateLimiter

      attr_reader :objid, :stay, :greenlighted, :session_ttl, :potential_email_address

      # cust is only populated if the passphrase matches
      def process_params
        # NOTE: The parameter names should match what rodauth uses.
        @potential_email_address = params['login'].to_s.downcase.strip
        @passwd                  = self.class.normalize_password(params['password'])
        @stay                    = true # Keep sessions alive by default
        # The TTL write_session actually applies: the session middleware
        # re-applies the configured expire_after on every commit, and
        # IdentityResolution independently caps identity age at the same
        # value — nothing consumes a per-login TTL, so reporting anything
        # else (the old hardcoded 30 days) was a lie in the auth log.
        @session_ttl             = Onetime.session_config['expire_after'].to_i

        # M-4/#3516: gate BEFORE the argon2 passphrase comparison below, so a
        # locked-out subject never triggers an expensive password hash. Both
        # rate-limit keys derive from data already in hand here — the submitted
        # email (params) and the client IP (strategy metadata) — so the check
        # needs neither the customer lookup nor the comparison it precedes. This
        # runs inside the Base constructor (process_params fires there, see
        # #3516); a lockout therefore raises LimitExceeded from `.new`, which the
        # Otto request hook / Roda ErrorTranslator surface as 429 exactly as they
        # did when this check lived in raise_concerns.
        check_login_rate_limit!(login_rate_limit_email, login_rate_limit_ip)

        potential = Onetime::Customer.find_by_email(potential_email_address)

        # Held for the failure funnel in raise_concerns (#4339), which needs to
        # know whether the ATTEMPTED address belongs to a colonel and cannot
        # ask @cust — that is deliberately nil on every failure. Reusing the
        # lookup already made here keeps the failed-sign-in audit check free of
        # a second round trip on the path an attacker drives. nil is a
        # MEANINGFUL value: "looked, no such account", which records nothing.
        @potential_customer = potential

        # AUTHENTICATION IS AGAINST THE ATTEMPTED IDENTITY ONLY. Base#initialize
        # seeds @cust with strategy_result.user — whoever the request's session
        # already resolved to, which need not be the account the `login` param
        # names. Left standing on a mismatch, that seed handed the submitted
        # password a SECOND identity to try: a request carrying customer C's
        # session that submitted `login=X` with C's password sailed through
        # success? re-authenticated as C, the login param silently ignored —
        # and skipped the failure funnel, so the attempt against X was never
        # counted or audited. Full mode has no such fallback: Rodauth resolves
        # the account from the submitted `login` and verifies the password
        # against that account alone (its default already_logged_in is a no-op
        # and this app never configures it). So @cust is unconditionally
        # overwritten here — the attempted account when its passphrase matches,
        # nil otherwise — which makes raise_concerns the single failure funnel
        # for EVERY rejected credential, carried session or not.
        passwd_matches = potential ? potential.passphrase?(@passwd) : false
        @cust          = passwd_matches ? potential : nil
        @objid         = @cust.objid if @cust

        migrate_password_hash_if_needed(potential, @passwd) if passwd_matches
      end

      # Rehash legacy bcrypt passwords to argon2id on successful login.
      #
      # @param customer [Onetime::Customer] The authenticated customer
      # @param password [String] The verified plaintext password
      def migrate_password_hash_if_needed(customer, password)
        return if customer.argon2_hash?(customer.passphrase)

        customer.update_passphrase!(password)
        auth_logger.info 'Password hash migrated to argon2',
          {
            user_id: customer.objid,
            email: customer.obscure_email,
            action: 'password_hash_migration',
          }
      rescue StandardError => ex
        auth_logger.error 'Password hash migration failed',
          {
            user_id: customer.objid,
            email: customer.obscure_email,
            error: ex.message,
            action: 'password_hash_migration_failed',
          }
      end

      def raise_concerns
        # M-4: simple mode has no Rodauth lockout, so credential submissions are
        # throttled by the two-tier LoginRateLimiter. The lockout CHECK now runs
        # in process_params, ahead of the argon2 comparison, so a locked subject
        # never burns a password hash (#3516). Here we only RECORD the failure
        # for a subject that got past that gate — a read-only probe cannot be
        # placed after the failure it counts, so the two halves are split.

        return unless @cust.nil?

        # @cust is nil for unknown-email, wrong-password, AND a carried-session
        # request whose password matched nobody — process_params overwrites the
        # strategy_result.user seed unconditionally — so this is the single
        # failure funnel. Count the failed attempt before raising the
        # (deliberately non-enumerating) error.
        record_failed_login_attempt!(login_rate_limit_email, login_rate_limit_ip)

        # #4339: and audit it, when the address that was tried is a real
        # colonel account. Ordered before the raise for the same reason the
        # attempt count is — raise_form_error never returns.
        record_colonel_signin_failure(@potential_customer)

        # cust stays nil - error raised before we need it
        raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
      end

      def process
        unless success?
          # Defense-in-depth recheck, not the production failure funnel:
          # process_params pins @cust to the attempted account or nil, and
          # raise_concerns raises on nil, so reaching here with success? false
          # means the state process_params verified went stale between
          # construction and now (e.g. a concurrent password change). The two
          # rejection sites stay mutually exclusive per attempt (raise_concerns
          # runs first and raises), which keeps the at-most-one-event property.
          #
          # Attribution — log line and audit event alike — is the ATTEMPTED
          # identity from the `login` param, never strategy_result.user:
          # exactly what full mode's after_login_failure logs (the submitted
          # `login`) and what the funnel above records. The event answers
          # "which admin account is being tried"; a carried-session identity
          # here would be a false brute-force signal about an account nobody
          # was working on. nil (unknown address) records nothing, per the
          # helper's contract.
          auth_logger.warn 'Login failed',
            {
              email: @potential_customer&.obscure_email,
              role: @potential_customer&.role,
              session_id: safe_session_id,
              ip: @strategy_result.metadata[:ip],
              reason: :invalid_credentials,
            }

          record_colonel_signin_failure(@potential_customer)

          raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
        end

        # M-4: credentials verified (success? is true past this point), so drop
        # any accumulated failed-attempt/lockout state for this subject. Covers
        # the greenlight, pending, and suspended paths uniformly — a valid
        # credential is never a brute-force attempt.
        clear_login_rate_limit!(login_rate_limit_email, login_rate_limit_ip)

        # Suspended accounts cannot log in. This check runs AFTER credential
        # verification (success? above), so the message is only ever shown to
        # someone holding valid credentials — it confirms nothing to an
        # attacker probing for account existence (non-enumerating), while
        # staying clear for the legitimate owner.
        if cust.suspended?
          auth_logger.warn 'Login rejected: account suspended',
            {
              user_id: cust.objid,
              email: cust.obscure_email,
              session_id: safe_session_id,
              ip: @strategy_result.metadata[:ip],
              reason: :suspended,
            }

          raise_form_error 'This account has been suspended. Contact support for assistance.',
            field: 'email',
            error_type: 'suspended'
        end

        if cust.pending?
          auth_logger.info 'Login pending customer verification',
            {
              customer_id: cust.objid,
              email: cust.obscure_email,
              role: cust.role,
              session_id: safe_session_id,
              status: :pending,
            }

          # Resend the verification email only when autoverify is disabled.
          # With autoverify enabled, registration sets verified=true and skips
          # email verification entirely (see CreateAccount), so a pending
          # account under autoverify can only mean the site admin manually set
          # verified=false (e.g. for moderation) or autoverify was enabled
          # after this account signed up — in both cases resending a
          # verification email on every login would be spam.
          autoverify = OT.conf.dig('site', 'authentication', 'autoverify')
          unless autoverify.to_s == 'true'
            # Help pending accounts finish the normal verification flow by
            # resending the email (link valid for 24h).
            auth_logger.info 'Resending verification email (autoverify disabled)',
              {
                customer_id: cust.objid,
                email: cust.obscure_email,
              }

            send_verification_email nil
          end

          return success_data
        end

        @greenlighted = true

        # Clear old session data to prevent session fixation
        sess.clear
        sess.replace! if sess.respond_to?(:replace!)

        # Set session authentication data
        sess['external_id']      = cust.extid
        sess['authenticated']    = true
        sess['authenticated_at'] = Familia.now.to_i

        # Role is stored on the customer record and managed via CLI:
        # bin/ots customers role promote user@example.com --role colonel
        sess['role'] = cust.role
        cust.save

        auth_logger.info 'Login successful',
          {
            user_id: cust.objid,
            email: cust.obscure_email,
            role: cust.role,
            session_id: safe_session_id,
            ip: @strategy_result.metadata[:ip],
            stay: stay,
            session_ttl: session_ttl,
          }

        record_colonel_signin

        success_data
      end

      def success_data
        { objid: cust.objid, role: cust.role }
      end

      def success?
        # Least-capability auth: a session authenticates only when the supplied
        # passphrase matches the ATTEMPTED customer's own passphrase. @cust is
        # the account process_params resolved from the `login` param, or nil —
        # never strategy_result.user (process_params overwrites the seed), so
        # the identity this recheck verifies is the identity the session will
        # be established as. The equal? guard makes that invariant local: if
        # bookkeeping ever drifts and @cust is not the very object the login
        # param resolved to, this fails closed rather than vouch for a
        # different account — the shape of the original defect (#4361 fixed
        # its audit-attribution half; this fixed the authentication half),
        # where the carried session identity got a second chance at the
        # password.
        #
        # A colonel-passphrase-as-any-customer branch is deliberately absent: any
        # such implicit impersonation would mint an authenticated-as-arbitrary
        # -customer session with no ColonelAuditEvent (see ticket 52). If a genuine
        # impersonation need ever arises it must be an explicit operation gated by
        # both authz layers (Otto role=colonel + verify_one_of_roles!(colonel:true))
        # that writes an audit event on every use — never a clause here.
        return false if cust.nil? || cust.anonymous?
        return false unless cust.equal?(@potential_customer)

        cust.passphrase?(@passwd)
      end

      private

      # Record a colonel.signin event when the session just established belongs
      # to a colonel. The SIMPLE-auth-mode counterpart to
      # Auth::Operations::SyncSession#record_colonel_signin (full mode never
      # reaches this class; simple mode never loads the auth app).
      #
      # ## Why this exists
      #
      # Nearly all colonel activity is reads, and reads never audit by design
      # (CONTRACT 4), so the audit screen reads empty even while operators are
      # in the console daily. Session establishment is the one honest signal of
      # operator PRESENCE, as opposed to operator writes.
      #
      # ## Success only, exactly once
      #
      # This sits inside the greenlighted branch, past credential verification
      # and the suspended/pending rejections, so only a completed login reaches
      # it — once per login, not once per request (the session is authenticated
      # from here on and never re-enters this class).
      #
      # Failures are recorded ELSEWHERE, not nowhere (#4339). This comment used
      # to say a failed login recorded nothing, on the grounds that the audit
      # set is capped by COUNT with no TTL, so an event an unauthenticated
      # caller can trigger is a log-eviction primitive — enough failed logins
      # would flush the real destructive-action trail. That is still true of
      # THIS write, which is why it stays a `.record` into `events`. It stopped
      # being a reason to record nothing at all once the store grew a separate
      # anonymous-telemetry budget: see #record_colonel_signin_failure, which
      # writes a failed attempt against a colonel account to `security_events`,
      # where a flood can only ever evict other anonymous telemetry.
      def record_colonel_signin
        return unless cust && cust.role.to_s == 'colonel'

        Onetime::ColonelAuditEvent.record(
          actor: cust.extid,
          verb: Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN,
          target: cust.extid,
          result: :success,
          detail: {
            auth_method: 'password',
            ip: @strategy_result&.metadata&.[](:ip),
          },
        )
      rescue StandardError => ex
        # Best-effort: a login must never fail because its audit event could not
        # be assembled.
        OT.le('[colonel.signin] audit record failed', exception: ex)
      end

      # Record the SIMPLE-auth-mode half of colonel.signin_failed (#4339). Full
      # mode's counterpart is the Rodauth after_login_failure hook in
      # Auth::Config::Hooks::Login; the guard, the obscured target and the
      # event shape are shared by Onetime::ColonelSigninFailure so the two
      # modes cannot drift.
      #
      # `customer` is ALWAYS @potential_customer — the account
      # process_params resolved from the submitted `login` param, nil when the
      # address matched nothing. BOTH rejection branches pass it, so simple
      # mode attributes to the attempted identity exactly as full mode does
      # (the Rodauth hook hands the helper the submitted `login:`). @cust would
      # name the same object today — process_params pins it to the attempted
      # account or nil — but attribution must not ride on that bookkeeping, so
      # the parameter stays explicit. No `login:` is passed and no second
      # lookup happens. The helper never raises and never writes for a
      # non-colonel, which is why there is no rescue and no role check here.
      #
      # No throttle: the event lands in `security_events`, whose budget is
      # trimmed independently of the operator trail. Budget separation IS the
      # control — see the WRITE-FREQUENCY INVARIANT on
      # Onetime::ColonelAuditEvent — so this needs no bound of its own beyond
      # the login rate limiter that already gates the surrounding path.
      def record_colonel_signin_failure(customer)
        Onetime::ColonelSigninFailure.record(auth_mode: 'simple', customer: customer)
      end

      # Rate-limit subject halves passed separately to the two-tier
      # LoginRateLimiter (email drives the global backstop; email+ip the tight
      # per-origin tier). See LoginRateLimiter for why neither half alone is a
      # sufficient key. IP comes from the same strategy metadata the log lines
      # read; both are available after process_params.
      def login_rate_limit_email
        @potential_email_address
      end

      def login_rate_limit_ip
        @strategy_result&.metadata&.[](:ip)
      end

      def form_fields
        { objid: objid }
      end
    end
  end
end
