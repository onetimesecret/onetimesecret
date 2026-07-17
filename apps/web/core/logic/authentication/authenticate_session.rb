# apps/web/core/logic/authentication/authenticate_session.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'
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
        @session_ttl             = (stay ? 30.days : 20.minutes).to_i

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

          # Do not send an email to a someone that's just logged-in with a basic
          # authmode account where verified=false and autoverify is disabled. With
          # autoverify disabled, the registration flow sets verified=true and
          # skips the email verification process. However, if the site admin
          # has manually set verified=false on the account (e.g. for moderation
          # purposes), we don't want to spam them with verification emails
          # every time they log in. This scenario could also happen if the
          # site configuration changes after users have already signed up
          # but not yet verified.
          autoverify = OT.conf.dig('site', 'authentication', 'autoverify')
          unless autoverify.to_s == 'true'
            # When autoverify is enabled, proactively help pending accounts
            # get verified by resending the verification email (valid for 24h)
            auth_logger.info 'Resending verification email (autoverify mode)',
              {
                customer_id: cust.objid,
                email: cust.obscure_email,
              }

            send_verification_email nil

            verification_msg = I18n.t(
              'web.COMMON.verification_sent_to',
              locale: locale,
              default: 'Verification sent to',
            )
            msg              = "#{verification_msg} #{cust.email}."
            set_info_message(msg)
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
        # -customer session with no AdminAuditEvent (see ticket 52). If a genuine
        # impersonation need ever arises it must be an explicit operation gated by
        # both authz layers (Otto role=colonel + verify_one_of_roles!(colonel:true))
        # that writes an audit event on every use — never a clause here.
        !cust&.anonymous? && cust.passphrase?(@passwd)
      end

      private

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
