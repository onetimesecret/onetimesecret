# apps/web/core/spec/logic/authentication/authenticate_session_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Core::Logic::Authentication::AuthenticateSession do
  subject(:logic) { described_class.new(strategy_result, params, 'en') }

  let(:test_email) { 'test@example.com' }
  let(:test_password) { 'password123' }
  let(:session_data) { {} }

  let(:rack_session) do
    session = double('RackSession')
    allow(session).to receive(:id).and_return(double(public_id: 'sess_def456'))
    allow(session).to receive(:clear)
    allow(session).to receive(:replace!)
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    session
  end

  let(:customer) do
    cust = double('Customer')
    allow(cust).to receive(:passphrase?).with(test_password).and_return(true)
    allow(cust).to receive(:passphrase?).with('definitely-wrong').and_return(false)
    allow(cust).to receive_messages(
      objid: 'cust_test123',
      custid: test_email,
      email: test_email,
      extid: 'ur_test123',
      verified: 'true',
      obscure_email: 'te***@example.com',
      role: :customer,
      anonymous?: false,
      pending?: false,
      suspended?: false,
      argon2_hash?: true,
      passphrase: '$argon2id$...'
    )
    allow(cust).to receive(:role=)
    allow(cust).to receive(:save)
    cust
  end

  let(:anonymous_customer) do
    anon = double('AnonymousCustomer')
    allow(anon).to receive_messages(
      anonymous?: true,
      obscure_email: 'anonymous',
      objid: nil,
      role: :anonymous
    )
    anon
  end

  let(:strategy_result) do
    result = double('StrategyResult')
    allow(result).to receive_messages(
      session: rack_session,
      user: anonymous_customer,
      metadata: { ip: '127.0.0.1' },
      authenticated?: false
    )
    result
  end

  let(:params) { { 'login' => test_email, 'password' => test_password } }

  let(:mock_logger) { double('Logger', info: nil, warn: nil, error: nil, debug: nil) }

  before do
    # I18n setup
    I18n.available_locales = [:en] unless I18n.available_locales.include?(:en)
    I18n.default_locale = :en

    # Stub OT.conf
    allow(OT).to receive_messages(
      conf: {
        'site' => {
          'authentication' => {
            'autoverify' => nil,
          },
        },
        'features' => {},
      },
      default_locale: 'en'
    )

    # Stub customer lookup - use a lambda so we can override in tests
    allow(Onetime::Customer).to receive(:find_by_email).and_return(customer)
    # Note: Customer.anonymous singleton removed in PR #2733 - anonymous users have cust=nil

    # Stub logging on the class so it works before subject is created
    allow_any_instance_of(described_class).to receive(:auth_logger).and_return(mock_logger)

    # M-4: stub the login rate limiter so unit specs never touch Redis. Real
    # throttling behavior is covered in the dedicated 'login rate limiting'
    # describe below by overriding these per-example.
    allow_any_instance_of(described_class).to receive(:check_login_rate_limit!)
    allow_any_instance_of(described_class).to receive(:record_failed_login_attempt!)
    allow_any_instance_of(described_class).to receive(:clear_login_rate_limit!)
  end

  describe '#process_params' do
    it 'normalizes and stores the potential email address' do
      logic.process_params
      expect(logic.potential_email_address).to eq('test@example.com')
    end

    it 'strips and downcases the email' do
      params['login'] = '  TEST@EXAMPLE.COM  '
      logic.process_params
      expect(logic.potential_email_address).to eq('test@example.com')
    end

    it 'sets stay to true by default' do
      logic.process_params
      expect(logic.stay).to be true
    end

    it 'reports the session TTL the middleware actually applies (configured expire_after)' do
      logic.process_params
      # session_config falls back to SESSION_DEFAULTS (24h) when site.session
      # is not configured — the same value write_session re-applies per commit.
      expect(logic.session_ttl).to eq(86_400)
      expect(logic.session_ttl).to eq(Onetime.session_config['expire_after'].to_i)
    end

    it 'sets objid when customer exists and passphrase matches' do
      logic.process_params
      expect(logic.objid).to eq('cust_test123')
    end

    context 'when passphrase does not match' do
      let(:customer) do
        cust = double('Customer')
        allow(cust).to receive(:passphrase?).and_return(false)
        allow(cust).to receive_messages(
          objid: 'cust_test123',
          email: test_email,
          argon2_hash?: true,
          passphrase: '$argon2id$...'
        )
        cust
      end

      it 'does not set objid' do
        logic.process_params
        expect(logic.objid).to be_nil
      end
    end

    context 'when customer does not exist' do
      before do
        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      end

      it 'does not set objid' do
        logic.process_params
        expect(logic.objid).to be_nil
      end
    end
  end

  describe '#raise_concerns' do
    # Note: Anonymous users have @cust = nil (PR #2733 removed Customer.anonymous).
    # The raise_concerns method handles the nil case by checking anonymous_user?.
    # Actual authentication error handling happens in #process via success? check.

    context 'when customer exists and authenticated' do
      before do
        logic.process_params
      end

      it 'does not raise any concerns' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when authentication failed (password mismatch)' do
      let(:customer) do
        cust = double('Customer')
        allow(cust).to receive(:passphrase?).and_return(false)
        allow(cust).to receive_messages(
          objid: 'cust_test123',
          email: test_email,
          # The failure funnel asks the ATTEMPTED account for its role (#4339);
          # a real Customer always answers, so the double must too.
          role: :customer,
          argon2_hash?: true,
          passphrase: '$argon2id$...'
        )
        cust
      end

      # Production-accurate failure path: an anonymous login POST carries
      # user=nil (PR #2733), so @cust starts nil (Logic::Base#initialize) and
      # stays nil on a mismatch. That nil is what makes raise_concerns the
      # single failure funnel; a non-nil .user would let it return early.
      let(:strategy_result) do
        result = double('StrategyResult')
        allow(result).to receive_messages(
          session: rack_session,
          user: nil,
          auth_method: :anonymous,
          metadata: { ip: '127.0.0.1' },
          authenticated?: false
        )
        result
      end

      it 'raises a non-enumerating form error for the unmatched credential' do
        # @cust stays nil when the passphrase does not match, so raise_concerns
        # is the single failure funnel that rejects the attempt.
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, 'Invalid email or password')
      end
    end
  end

  describe '#process' do
    before do
      logic.process_params
    end

    context 'when authentication is successful' do
      context 'and customer is pending' do
        before do
          allow(customer).to receive(:pending?).and_return(true)
          allow(logic).to receive(:send_verification_email)
        end

        context 'when autoverify is disabled' do
          before do
            allow(OT).to receive(:conf).and_return({
              'site' => {
                'authentication' => {
                  'autoverify' => 'false',
                },
              },
            })
          end

          it 'sends verification email' do
            expect(logic).to receive(:send_verification_email).with(nil)
            logic.process
          end

          it 'logs pending customer login' do
            expect(mock_logger).to receive(:info).with('Login pending customer verification', hash_including(:customer_id, :email))
            expect(mock_logger).to receive(:info).with('Resending verification email (autoverify disabled)', hash_including(:customer_id, :email))
            logic.process
          end
        end

        context 'when autoverify is enabled' do
          before do
            allow(OT).to receive(:conf).and_return({
              'site' => {
                'authentication' => {
                  'autoverify' => 'true',
                },
              },
            })
          end

          it 'does not send verification email' do
            expect(logic).not_to receive(:send_verification_email)
            logic.process
          end
        end
      end

      context 'and customer is not pending' do
        before do
          allow(customer).to receive(:pending?).and_return(false)
        end

        it 'sets greenlighted to true' do
          logic.process
          expect(logic.greenlighted).to be true
        end

        it 'regenerates the session' do
          expect(rack_session).to receive(:clear)
          expect(rack_session).to receive(:replace!)
          logic.process
        end

        it 'sets session authentication fields' do
          logic.process
          expect(session_data['external_id']).to eq('ur_test123')
          expect(session_data['authenticated']).to be true
          expect(session_data['authenticated_at']).to be_a(Integer)
        end

        it 'saves customer' do
          expect(customer).to receive(:save)
          logic.process
        end

        it 'logs successful login' do
          expect(mock_logger).to receive(:info).with('Login successful', hash_including(:user_id, :email, :role))
          logic.process
        end

        it 'stores customer role in session' do
          # Role is managed via CLI (bin/ots customers role promote) and stored on customer record
          # Authentication just reads the existing role and stores it in session
          allow(customer).to receive(:role).and_return('colonel')
          logic.process
          expect(session_data['role']).to eq('colonel')
        end
      end
    end

    context 'when authentication fails' do
      before do
        allow(customer).to receive(:passphrase?).with(test_password).and_return(false)
        # Need to re-run process_params after changing the stub
        logic.process_params
      end

      it 'logs failure and raises form error' do
        expect(mock_logger).to receive(:warn).with('Login failed', hash_including(:email, :reason))
        expect { logic.process }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to eq('Invalid email or password')
        end
      end
    end
  end

  # Simple auth mode's session-establishment site for the colonel.signin audit
  # event (full mode's counterpart is Auth::Operations::SyncSession). Colonel
  # activity is overwhelmingly reads, and reads never audit by design
  # (CONTRACT 4), so session establishment is the one signal of operator
  # presence the trail can carry.
  describe 'colonel.signin audit event' do
    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      # A wrong-credential example below now reaches the failed-sign-in emitter
      # (#4339); stub the security trail too so no example here touches Valkey.
      allow(Onetime::ColonelAuditEvent).to receive(:record_security)
      logic.process_params
    end

    it 'records nothing for a non-colonel login' do
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    context 'when the customer is a colonel' do
      before { allow(customer).to receive(:role).and_return('colonel') }

      it 'records one colonel.signin event with public identities only' do
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: 'ur_test123',
          verb: 'colonel.signin',
          target: 'ur_test123',
          result: :success,
          detail: { auth_method: 'password', ip: '127.0.0.1' },
        )
      end

      # The hard constraint, unchanged by #4339: the OPERATOR trail is capped by
      # COUNT with no TTL, so an event a failed login can trigger would be a
      # log-eviction primitive against it. A failure still writes nothing here —
      # it writes to the separately-budgeted security trail instead (see the
      # colonel.signin_failed group below).
      it 'records NOTHING on the operator trail when the credentials are wrong' do
        params['password'] = 'definitely-wrong'
        logic.process_params

        expect { logic.process }.to raise_error(Onetime::FormError)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'records NOTHING when the account is suspended' do
        allow(customer).to receive(:suspended?).and_return(true)

        expect { logic.process }.to raise_error(Onetime::FormError)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'records NOTHING for a pending (unverified) account' do
        allow(customer).to receive(:pending?).and_return(true)
        allow(logic).to receive(:send_verification_email)

        logic.process

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end
  end

  # Simple auth mode's half of colonel.signin_failed (#4339). Full mode's half
  # is the Rodauth after_login_failure hook, covered in
  # apps/web/auth/spec/config/hooks/login_colonel_signin_failure_spec.rb; both
  # go through Onetime::ColonelSigninFailure, so the shape is pinned twice on
  # purpose — the two modes must never drift.
  #
  # These examples drive raise_concerns, which is the PRODUCTION failure funnel:
  # an anonymous login POST carries user=nil (PR #2733), so @cust is nil for
  # both unknown-email and wrong-password and process is never reached.
  describe 'colonel.signin_failed audit event (#4339)' do
    # A colonel whose passphrase does NOT match the submitted one.
    let(:customer) do
      cust = double('Customer')
      allow(cust).to receive(:passphrase?).and_return(false)
      allow(cust).to receive_messages(
        objid: 'cust_colonel',
        email: 'colonel@example.com',
        obscure_email: 'co***@e***.com',
        role: 'colonel',
        anonymous?: false,
        argon2_hash?: true,
        passphrase: '$argon2id$...'
      )
      cust
    end

    let(:strategy_result) do
      result = double('StrategyResult')
      allow(result).to receive_messages(
        session: rack_session,
        user: nil,
        auth_method: :anonymous,
        metadata: { ip: '127.0.0.1' },
        authenticated?: false
      )
      result
    end

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_security)
      allow(OT).to receive(:le)
    end

    it 'records exactly one event, with the OBSCURED email as target' do
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError)

      # actor is 'anonymous', not 'unknown': the caller is unauthenticated by
      # construction here, and nobody has proven they are this account, so an
      # extid would be the wrong identity to stamp as well as a leak.
      expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
        actor: 'anonymous',
        verb: 'colonel.signin_failed',
        target: 'co***@e***.com',
        result: :failure,
        detail: { auth_mode: 'simple', failure_reason: 'invalid_credentials' },
      )
    end

    it 'uses the single-sourced verb constant (both auth modes must agree)' do
      expect(Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN_FAILED).to eq('colonel.signin_failed')
    end

    # The verb string choice, pinned: ColonelAuditReader matches a verb exactly
    # or as a DOTTED category prefix, so a `colonel.signin.failed` spelling
    # would silently widen the existing `colonel.signin` filter to include
    # failures. Sibling verbs keep "who signed in" and "who tried" separable.
    it 'is not a dotted child of colonel.signin' do
      expect(Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN_FAILED).not_to start_with(
        "#{Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN}.",
      )
    end

    it 'never writes the operator trail (its budget is the whole point)' do
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError)

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    context 'when the attempted account is not a colonel' do
      before { allow(customer).to receive(:role).and_return('customer') }

      it 'records nothing (CONTRACT 4: not an admin account)' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
      end
    end

    context 'when the attempted account does not exist' do
      before { allow(Onetime::Customer).to receive(:find_by_email).and_return(nil) }

      it 'records nothing, so arbitrary submitted addresses cannot mint events' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
      end

      it 'does not re-look-up the address the failure funnel already resolved' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)

        # process_params (which runs in the constructor) did the ONE lookup and
        # the funnel reuses its result — nil here meaning "already looked, no
        # such account" — rather than paying a second round trip on the path an
        # attacker drives.
        expect(Onetime::Customer).to have_received(:find_by_email).once
      end
    end

    it 'still rejects the login when the audit write blows up' do
      allow(Onetime::ColonelAuditEvent).to receive(:record_security).and_raise(StandardError, 'boom')

      # The failure response is unaffected: the caller sees the same
      # non-enumerating form error, never the audit exception.
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, 'Invalid email or password')
      expect(OT).to have_received(:le).with('[colonel.signin_failed] audit record failed', hash_including(:exception))
    end

    # The second credential-rejection branch: reachable only when the request
    # already carried a customer, so raise_concerns returned and #process
    # rejected on success?. Mutually exclusive with the funnel above, which is
    # what bounds this to one event per attempt.
    context 'when the rejection happens in #process instead' do
      let(:strategy_result) do
        result = double('StrategyResult')
        allow(result).to receive_messages(
          session: rack_session,
          user: customer,
          auth_method: :session,
          metadata: { ip: '127.0.0.1' },
          authenticated?: false
        )
        result
      end

      it 'records exactly one event there too' do
        expect { logic.process }.to raise_error(Onetime::FormError)

        expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
          hash_including(verb: 'colonel.signin_failed', target: 'co***@e***.com', result: :failure),
        )
      end
    end
  end

  describe '#success?' do
    context 'when customer is not anonymous and passphrase matches' do
      before do
        logic.process_params
      end

      it 'returns true' do
        expect(logic.success?).to be true
      end
    end

    context 'when customer does not exist' do
      before do
        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
        logic.process_params
      end

      it 'returns false' do
        expect(logic.success?).to be false
      end
    end

    context 'when passphrase does not match' do
      let(:customer) do
        cust = double('Customer')
        allow(cust).to receive(:passphrase?).and_return(false)
        allow(cust).to receive_messages(
          objid: 'cust_test123',
          email: test_email,
          anonymous?: false,
          argon2_hash?: true,
          passphrase: '$argon2id$...'
        )
        cust
      end

      before do
        logic.process_params
      end

      it 'returns false' do
        expect(logic.success?).to be false
      end
    end
  end

  describe '.normalize_password' do
    it 'strips whitespace from password' do
      result = described_class.normalize_password('  password123  ')
      expect(result).to eq('password123')
    end

    it 'limits password length to max_length' do
      long_password = 'a' * 200
      result = described_class.normalize_password(long_password, 10)
      expect(result.length).to eq(10)
    end

    it 'handles nil password' do
      result = described_class.normalize_password(nil)
      expect(result).to eq('')
    end
  end

  describe 'login rate limiting (M-4) — pre-gated lockout' do
    # #3516/#3807 moved check_login_rate_limit! ahead of the argon2 comparison,
    # into process_params, which fires from Onetime::Logic::Base#initialize. A
    # locked subject therefore raises at construction — before any credential is
    # evaluated and before record_failed_login_attempt! (which lives only in
    # raise_concerns) can run. Arm the raise via any_instance so the gate is
    # active before .new, then assert against described_class.new to exercise
    # the real gated path rather than a re-invocation on an already-built object.
    before do
      allow_any_instance_of(described_class).to receive(:check_login_rate_limit!).and_raise(
        Onetime::LimitExceeded.new(
          'Too many login attempts. Please try again later.',
          retry_after: 1800,
          max_attempts: 5,
        ),
      )
    end

    it 'raises LimitExceeded at construction, before evaluating credentials' do
      expect_any_instance_of(described_class).not_to receive(:record_failed_login_attempt!)
      expect { described_class.new(strategy_result, params, 'en') }.to raise_error(Onetime::LimitExceeded)
    end
  end

  describe 'login rate limiting (M-4)' do
    before do
      logic.process_params
    end

    context 'on a failed credential attempt' do
      let(:customer) do
        cust = double('Customer')
        allow(cust).to receive(:passphrase?).and_return(false)
        allow(cust).to receive_messages(
          objid: 'cust_test123',
          email: test_email,
          # See the note on the #raise_concerns double: the failure funnel asks
          # the attempted account for its role (#4339).
          role: :customer,
          argon2_hash?: true,
          passphrase: '$argon2id$...'
        )
        cust
      end

      # Production-accurate failure path: anonymous login POST has user=nil
      # (PR #2733), so @cust starts nil and stays nil on a mismatch, making
      # raise_concerns reach the record + raise funnel.
      let(:strategy_result) do
        result = double('StrategyResult')
        allow(result).to receive_messages(
          session: rack_session,
          user: nil,
          auth_method: :anonymous,
          metadata: { ip: '127.0.0.1' },
          authenticated?: false
        )
        result
      end

      it 'records a failed login attempt before raising the form error' do
        # raise_form_error aborts raise_concerns, so a satisfied expectation
        # here proves the record call precedes the raise.
        expect(logic).to receive(:record_failed_login_attempt!)
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
      end

      it 'scopes the subject to the email + ip two-tier keys' do
        # Two-tier limiter (RL-2/RL-3): email drives the global backstop, ip the
        # tight per-origin tier, passed as separate args (not an "email|ip"
        # composite) so a nil ip cleanly skips the tight tier.
        expect(logic).to receive(:record_failed_login_attempt!).with(test_email, '127.0.0.1')
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
      end
    end

    context 'on a successful login' do
      before do
        allow(customer).to receive(:pending?).and_return(false)
      end

      it 'clears the login rate limit for the subject' do
        expect(logic).to receive(:clear_login_rate_limit!).with(test_email, '127.0.0.1')
        logic.process
      end
    end
  end

  describe 'security considerations' do
    it 'does not log the actual password' do
      expect(mock_logger).not_to receive(:info).with(a_string_matching(/password123/))
      expect(mock_logger).not_to receive(:warn).with(a_string_matching(/password123/))
      logic.process_params
    end

    it 'uses obscured email in logs for successful login' do
      logic.process_params
      expect(mock_logger).to receive(:info).with('Login successful', hash_including(email: 'te***@example.com'))
      logic.process
    end
  end

  # Regression for #3812: the synchronous verification-email path bypasses the
  # EmailWorker locale-normalization chokepoint. A blank @locale ("") is truthy,
  # so it would slip past the delivery site's `||` into an invalid I18n lookup
  # (:"") and raise I18n::InvalidLocale, silently failing the email.
  describe '#send_verification_email locale normalization' do
    subject(:blank_locale_logic) { described_class.new(strategy_result, params, '') }

    let(:secret) do
      double('Secret', identifier: 'sec_abc123').tap do |s|
        allow(s).to receive(:verification=)
        allow(s).to receive(:custid=)
        allow(s).to receive(:save)
      end
    end

    before do
      allow(customer).to receive(:reset_secret=)
      allow(Onetime::Receipt).to receive(:spawn_pair).and_return([double('Receipt'), secret])
      allow(Onetime::Mail::Mailer).to receive(:deliver)
    end

    it 'reproduces the blank @locale from a blank locale param' do
      expect(blank_locale_logic.locale).to eq('')
    end

    it 'delivers the welcome email with the default locale when @locale is blank' do
      blank_locale_logic.send(:send_verification_email, nil, customer: customer)

      expect(Onetime::Mail::Mailer).to have_received(:deliver).with(
        :welcome,
        hash_including(email_address: test_email),
        locale: OT.default_locale,
      )
    end
  end
end
