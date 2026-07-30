# apps/web/auth/operations/customers/diagnose.rb
#
# frozen_string_literal: true

require 'onetime/operations/ratelimit/inspect'

module Auth
  module Operations
    module Customers
      # Aggregate every signal relevant to "this user cannot log in or sign up"
      # into one read-out: Redis customer state, the Rodauth account row and its
      # sidecar tables (status, lockout, verification/reset keys, MFA, sessions,
      # authentication audit log) and the login rate limiter.
      #
      # The ONE implementation of the account-diagnose verb. The colonel API
      # endpoint (`GET /api/colonel/users/:user_id/diagnostics`) and the
      # `bin/ots customers diagnose` CLI are thin adapters over it, so support
      # staff get the same answer with or without SSH access.
      #
      # READ-ONLY: mutates nothing, records NO AdminAuditEvent (epic #20
      # CONTRACT 4 — same posture as Show and RateLimit::Inspect).
      #
      # Every section degrades independently (`available: false` + reason)
      # rather than failing the whole diagnosis: a support agent triaging a
      # login complaint needs whatever sections ARE reachable, especially when
      # one datastore being down is itself the cause.
      #
      # Resolution accepts the same identifiers as Show (extid, email, objid, or
      # a pre-resolved Customer) PLUS an email-only fallback: when no Customer
      # resolves but the identifier is an email, the authdb is still consulted
      # directly so an orphaned accounts row (auth account without a customer
      # record — a real can't-login cause) is diagnosed instead of 404ing.
      #
      # One section-builder per Rodauth sidecar table; splitting them apart
      # would hide the read-out's shape.
      # rubocop:disable Metrics/ClassLength
      class Diagnose
        # Rodauth account_statuses seed rows (001_initial.rb) — fixed ids.
        STATUS_NAMES = { 1 => 'unverified', 2 => 'verified', 3 => 'closed' }.freeze

        # SQL-backed section names, used to degrade them all at once when the
        # authdb itself is unreachable (simple mode, connection failure).
        AUTHDB_SECTIONS = [:auth_account, :mfa, :verification, :password_reset,
                           :lockout, :sessions, :audit_log].freeze

        DEFAULT_AUDIT_LOG_LIMIT = 20
        MAX_AUDIT_LOG_LIMIT     = 100

        # How long an unclicked verification email can sit before the account
        # is flagged as stuck (the user most likely never received it).
        VERIFICATION_STALE_AFTER = 24 * 60 * 60

        # `findings` is the triage summary derived from `sections`: an array of
        # { severity:, code:, message: } hashes, severity-ordered. `sections`
        # holds the raw per-source read-outs keyed by section name.
        Result = Data.define(:customer, :sections, :findings) do
          def found?
            !customer.nil? || sections.dig(:auth_account, :found) == true
          end
        end

        SEVERITY_ORDER = { critical: 0, warning: 1, info: 2 }.freeze

        # @param identifier [String, nil] extid, email, or objid
        # @param customer [Onetime::Customer, nil] a pre-resolved customer
        #   (takes precedence over identifier for customer resolution; the
        #   identifier is still used for the email-only authdb fallback)
        # @param audit_log_limit [Integer] newest-first audit rows to include
        def initialize(identifier: nil, customer: nil, audit_log_limit: DEFAULT_AUDIT_LOG_LIMIT)
          @identifier      = identifier.to_s.strip
          @customer        = customer
          @audit_log_limit = audit_log_limit.to_i.clamp(1, MAX_AUDIT_LOG_LIMIT)
        end

        # @return [Result]
        def call
          customer = @customer || resolve(@identifier)
          customer = nil unless customer&.exists?

          # The email the user is actually typing into the login form: the
          # customer's address when we have one, otherwise the raw identifier
          # (when it is an email). Drives the authdb fallback and the limiter.
          email = customer&.email.to_s
          email = normalized_email_identifier if email.empty?

          sections               = {}
          sections[:customer]    = customer_section(customer)
          sections.merge!(authdb_sections(customer, email))
          sections[:rate_limits] = rate_limits_section(email)

          Result.new(
            customer: customer,
            sections: sections,
            findings: derive_findings(sections),
          )
        end

        private

        # -- Resolution ---------------------------------------------------

        # Mirrors Show#resolve: extid/email first, then objid.
        def resolve(identifier)
          return nil if identifier.empty?

          Onetime::Customer.load_by_extid_or_email(identifier) ||
            Onetime::Customer.load(identifier)
        end

        def normalized_email_identifier
          return '' unless @identifier.include?('@')

          OT::Utils.normalize_email(@identifier)
        end

        # -- Customer (Redis) section --------------------------------------

        def customer_section(customer)
          return { found: false } if customer.nil?

          {
            found: true,
            extid: customer.extid,
            # FULL address (internal scope) — surfaces obscure client-side.
            email: customer.email,
            role: customer.role,
            verified: customer.verified?,
            suspended: customer.suspended?,
            suspended_at: customer.suspended_at,
            suspended_reason: customer.suspended_reason,
            created: customer.created,
            last_login: customer.last_login,
            locale: customer.locale,
            planid: customer.planid,
          }
        rescue StandardError => ex
          { found: true, error: "#{ex.class}: #{ex.message}" }
        end

        # -- Authdb (Rodauth) sections --------------------------------------

        # One connection check for all SQL-backed sections; each individual
        # query still degrades on its own so a single broken sidecar table
        # cannot blank out the rest.
        def authdb_sections(customer, email)
          db = auth_database
          return unavailable_authdb_sections('auth database unavailable (simple auth mode)') if db.nil?

          account = find_account(db, customer, email)
          if account.nil?
            return unavailable_authdb_sections('no auth account row').merge(
              auth_account: { available: true, found: false },
            )
          end

          account_id = account[:id]
          {
            auth_account: auth_account_section(db, account, customer),
            mfa: section(:mfa) { mfa_section(db, account_id) },
            verification: section(:verification) { verification_section(db, account_id) },
            password_reset: section(:password_reset) { password_reset_section(db, account_id) },
            lockout: section(:lockout) { lockout_section(db, account_id) },
            sessions: section(:sessions) { sessions_section(db, account_id) },
            audit_log: section(:audit_log) { audit_log_section(db, account_id) },
          }
        rescue StandardError => ex
          unavailable_authdb_sections("auth database error: #{ex.class}: #{ex.message}")
        end

        def auth_database
          Auth::Database.connection
        rescue StandardError
          nil
        end

        def unavailable_authdb_sections(reason)
          AUTHDB_SECTIONS.to_h do |name|
            [name, { available: false, reason: reason }.compact]
          end
        end

        # Wrap one SQL-backed section so a failing query degrades that section
        # only. Sections built here always carry `available: true`.
        def section(_name)
          yield.merge(available: true)
        rescue StandardError => ex
          { available: false, reason: "#{ex.class}: #{ex.message}" }
        end

        # By linked extid when we have a customer; by email otherwise (citext
        # on PG, so case-insensitive). The email arm is what surfaces orphaned
        # accounts rows.
        def find_account(db, customer, email)
          if customer
            row = db[:accounts].where(external_id: customer.extid).first
            return row if row
          end
          return nil if email.to_s.empty?

          db[:accounts].where(email: email).first
        end

        def auth_account_section(db, account, customer)
          section(:auth_account) do
            account_id = account[:id]
            {
              found: true,
              account_id: account_id,
              status: STATUS_NAMES.fetch(account[:status_id], "unknown (#{account[:status_id]})"),
              email: account[:email],
              email_matches_customer: customer.nil? || account[:email].to_s.casecmp?(customer.email.to_s),
              linked_extid: account[:external_id],
              created_at: epoch(account[:created_at]),
              has_password: db[:account_password_hashes].where(id: account_id).any?,
              password_changed_at: epoch(db[:account_password_change_times].where(id: account_id).get(:changed_at)),
              last_login_at: epoch(db[:account_activity_times].where(id: account_id).get(:last_login_at)),
              external_identities: db[:account_identities]
                .where(account_id: account_id)
                .select_map([:provider, :issuer])
                .map { |provider, issuer| { provider: provider, issuer: issuer } },
            }
          end
        end

        def mfa_section(db, account_id)
          otp = db[:account_otp_keys].where(id: account_id).first
          {
            otp_enabled: !otp.nil?,
            otp_failures: otp&.fetch(:num_failures, 0),
            webauthn_credentials: db[:account_webauthn_keys].where(account_id: account_id).count,
          }
        end

        def verification_section(db, account_id)
          row = db[:account_verification_keys].where(id: account_id).first
          {
            pending: !row.nil?,
            requested_at: epoch(row&.fetch(:requested_at, nil)),
            email_last_sent: epoch(row&.fetch(:email_last_sent, nil)),
          }
        end

        def password_reset_section(db, account_id)
          row = db[:account_password_reset_keys].where(id: account_id).first
          {
            pending: !row.nil?,
            deadline: epoch(row&.fetch(:deadline, nil)),
            email_last_sent: epoch(row&.fetch(:email_last_sent, nil)),
          }
        end

        def lockout_section(db, account_id)
          lockout  = db[:account_lockouts].where(id: account_id).first
          deadline = lockout&.fetch(:deadline, nil)
          {
            login_failures: db[:account_login_failures].where(id: account_id).get(:number).to_i,
            locked: !deadline.nil? && deadline > Time.now,
            deadline: epoch(deadline),
            email_last_sent: epoch(lockout&.fetch(:email_last_sent, nil)),
          }
        end

        def sessions_section(db, account_id)
          dataset = db[:account_active_session_keys].where(account_id: account_id)
          {
            active_count: dataset.count,
            last_use: epoch(dataset.max(:last_use)),
          }
        end

        # Newest-first tail of Rodauth's authentication audit log — the "what
        # actually happened when they tried" record (login, login_failure,
        # create_account, verify_account, lockout, ...).
        def audit_log_section(db, account_id)
          entries = db[:account_authentication_audit_logs]
            .where(account_id: account_id)
            .order(Sequel.desc(:at), Sequel.desc(:id))
            .limit(@audit_log_limit)
            .select(:at, :message, :metadata)
            .map do |row|
              {
                at: epoch(row[:at]),
                message: row[:message],
                metadata: plain_json(row[:metadata]),
              }
            end
          { entries: entries }
        end

        # -- Rate limiter section --------------------------------------------

        # The login limiter keys on the plain normalized email (see
        # login_rate_limiter.rb / RateLimit::Registry). Reuses the Inspect op
        # so the key derivation lives in exactly one place.
        def rate_limits_section(email)
          return { available: false, reason: 'no email to inspect' } if email.to_s.empty?

          result = Onetime::Operations::RateLimit::Inspect.new(kind: 'login', subject: email).call
          {
            available: true,
            entries: result.entries.map do |entry|
              { key: entry.key, ttl: entry.ttl, value: entry.value, exists: entry.exists }
            end,
          }
        rescue StandardError => ex
          { available: false, reason: "#{ex.class}: #{ex.message}" }
        end

        # -- Findings ---------------------------------------------------------

        # Turn the raw sections into the triage summary a support agent acts
        # on. Order: severity, then discovery order. Only states that explain
        # (or rule out) a login/signup failure become findings — this list is
        # the answer, the sections are the evidence.
        def derive_findings(sections)
          findings = []
          check_existence(sections, findings)
          check_customer_state(sections, findings)
          check_auth_account(sections, findings)
          check_lockout_and_limits(sections, findings)
          check_verification(sections, findings)
          findings.sort_by { |finding| SEVERITY_ORDER.fetch(finding[:severity], 99) }
        end

        def add(findings, severity, code, message)
          findings << { severity: severity, code: code, message: message }
        end

        def check_existence(sections, findings)
          customer_found = sections.dig(:customer, :found)
          account        = sections[:auth_account]

          if !customer_found && account[:found] != true
            add(
              findings,
              :critical,
              :not_found,
              'No customer record or auth account for this identifier in this region. ' \
              'If they insist they have an account, check the other regions.',
            )
          elsif !customer_found && account[:found]
            add(
              findings,
              :critical,
              :orphaned_auth_account,
              'Auth account exists but has no customer record — login will misbehave. ' \
              'Run `bin/ots customers doctor` for repair options.',
            )
          elsif customer_found && account[:available] && account[:found] != true
            add(
              findings,
              :critical,
              :missing_auth_account,
              'Customer record exists but has no auth account row — password login is impossible. ' \
              'Run `bin/ots customers sync-auth-accounts`.',
            )
          end
        end

        def check_customer_state(sections, findings)
          customer = sections[:customer]
          return unless customer[:found]

          return unless customer[:suspended]

          reason = customer[:suspended_reason].to_s
          add(
            findings,
            :critical,
            :suspended,
            "Customer is suspended#{" (#{reason})" unless reason.empty?} — all logins are refused.",
          )
        end

        def check_auth_account(sections, findings)
          account = sections[:auth_account]
          return unless account[:available] && account[:found]

          case account[:status]
          when 'closed'
            add(
              findings,
              :warning,
              :account_closed,
              'Auth account status is CLOSED — login is refused. The account was closed or purged.',
            )
          when 'unverified'
            add(
              findings,
              :warning,
              :unverified,
              'Auth account is UNVERIFIED — login is refused until the verification link is used.',
            )
          end

          if account[:email_matches_customer] == false
            add(
              findings,
              :critical,
              :email_drift,
              "Customer email and auth account email differ (auth side: #{account[:email]}) — " \
              'a half-completed email change. Login only works with the auth-side address.',
            )
          end

          return unless account[:has_password] == false

          identities = account[:external_identities] || []
          if identities.empty?
            add(
              findings,
              :warning,
              :no_password,
              'Auth account has NO password hash and no SSO identity — no working credential exists. ' \
              'Send a password reset.',
            )
          else
            providers = identities.map { |identity| identity[:provider] }.uniq.join(', ')
            add(
              findings,
              :info,
              :sso_only,
              "Account is SSO-only (#{providers}) — a password login attempt will always fail.",
            )
          end
        end

        def check_lockout_and_limits(sections, findings)
          lockout = sections[:lockout]
          if lockout[:available]
            if lockout[:locked]
              add(
                findings,
                :critical,
                :locked_out,
                'Rodauth lockout is ACTIVE (too many failed password attempts) — ' \
                "login refused until #{format_epoch(lockout[:deadline])} or an unlock email is used.",
              )
            elsif lockout[:login_failures].to_i.positive?
              add(
                findings,
                :info,
                :login_failures,
                "#{lockout[:login_failures]} consecutive failed password attempt(s) recorded — " \
                'likely a wrong or forgotten password.',
              )
            end
          end

          limits = sections[:rate_limits]
          return unless limits[:available]

          locked_keys = (limits[:entries] || []).select do |entry|
            entry[:exists] && entry[:key].start_with?('login:locked:')
          end
          return if locked_keys.empty?

          add(
            findings,
            :critical,
            :rate_limited,
            'Login rate limiter is ENGAGED for this email — attempts are rejected before ' \
            "authentication runs (TTL #{locked_keys.map { |entry| entry[:ttl] }.compact.max}s).",
          )
        end

        def check_verification(sections, findings)
          verification = sections[:verification]
          account      = sections[:auth_account]
          return unless verification[:available] && account[:available]
          return unless account[:found] && account[:status] == 'unverified'

          if verification[:pending]
            sent = verification[:email_last_sent]
            if sent && (Time.now.to_f - sent) > VERIFICATION_STALE_AFTER
              add(
                findings,
                :warning,
                :verification_stale,
                "Verification email was last sent #{format_epoch(sent)} and the link is still unused — " \
                'the user likely never received it. Check deliverability, then resend.',
              )
            end
          else
            add(
              findings,
              :critical,
              :verification_key_missing,
              'Account is unverified but NO verification key exists — the link can never work. ' \
              'Re-issue verification or verify manually.',
            )
          end
        end

        # -- Serialization helpers ---------------------------------------------

        # Sequel returns Time/DateTime; the wire shape is epoch seconds or nil.
        def epoch(value)
          return nil if value.nil?

          value.respond_to?(:to_time) ? value.to_time.to_f : value.to_f
        end

        def format_epoch(value)
          return '(unknown)' if value.nil?

          Time.at(value.to_f).utc.strftime('%Y-%m-%d %H:%M UTC')
        end

        # PG json/jsonb columns hydrate as Sequel wrapper objects; flatten to
        # plain Ruby so every adapter (JSON API, CLI) serializes identically.
        def plain_json(value)
          return value if value.nil? || value.is_a?(String)

          value.respond_to?(:to_h) ? value.to_h : value
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
