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

        return unless potential

        passwd_matches = potential.passphrase?(@passwd)
        @cust          = potential if passwd_matches
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

        # @cust is nil for BOTH unknown-email and wrong-password (only set when
        # the passphrase matches), so this is the single failure funnel. Count
        # the failed attempt before raising the (deliberately non-enumerating)
        # error.
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
          auth_logger.warn 'Login failed',
            {
              email: cust.obscure_email,
              role: cust.role,
              session_id: safe_session_id,
              ip: @strategy_result.metadata[:ip],
              reason: :invalid_credentials,
            }

          # The OTHER credential-rejection branch (#4339). raise_concerns is the
          # production funnel — @cust is nil there for both unknown-email and
          # wrong-password — so this one is only reached when the request
          # already carried a customer (strategy_result.user) and its passphrase
          # did not match. The two are mutually exclusive per attempt
          # (raise_concerns runs first and raises), which is what keeps the
          # at-most-one-event-per-attempt property.
          #
          # THE ATTEMPTED IDENTITY, NOT THE CARRIED ONE — the same
          # @potential_customer the funnel above uses. `cust` here is
          # strategy_result.user, i.e. whoever the REQUEST'S SESSION already
          # belonged to, which need not be the account named in the `login`
          # param: a request carrying colonel C's session that submits
          # `login=X` with a bad password would have recorded a failed attempt
          # against C, a false brute-force signal about an account nobody was
          # working on. What the event exists to answer is "which admin account
          # is being tried", so it attributes to the identity that was tried.
          # nil (unknown address) records nothing, per the helper's contract.
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
        # passphrase matches the target customer's own passphrase.
        #
        # A colonel-passphrase-as-any-customer branch is deliberately absent: any
        # such implicit impersonation would mint an authenticated-as-arbitrary
        # -customer session with no ColonelAuditEvent (see ticket 52). If a genuine
        # impersonation need ever arises it must be an explicit operation gated by
        # both authz layers (Otto role=colonel + verify_one_of_roles!(colonel:true))
        # that writes an audit event on every use — never a clause here.
        !cust&.anonymous? && cust.passphrase?(@passwd)
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
      # (the Rodauth hook hands the helper the submitted `login:`). Passing
      # `cust` from #process instead would target whoever the request's session
      # already belonged to. No `login:` is passed and no second lookup
      # happens. The helper never raises and never writes for a non-colonel,
      # which is why there is no rescue and no role check here.
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
