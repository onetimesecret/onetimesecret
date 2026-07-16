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

    it 'sets session TTL to 30 days when stay is true' do
      logic.process_params
      expect(logic.session_ttl).to eq(30 * 24 * 60 * 60) # 30 days in seconds
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
          allow(logic).to receive(:set_info_message)
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

          it 'sets info message about verification' do
            expect(logic).to receive(:set_info_message).with(a_string_matching(/#{Regexp.escape(test_email)}/))
            logic.process
          end

          it 'logs pending customer login' do
            expect(mock_logger).to receive(:info).with('Login pending customer verification', hash_including(:customer_id, :email))
            expect(mock_logger).to receive(:info).with('Resending verification email (autoverify mode)', hash_including(:customer_id, :email))
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

  describe 'login rate limiting (M-4)' do
    before do
      logic.process_params
    end

    context 'when the subject is already locked out' do
      before do
        allow(logic).to receive(:check_login_rate_limit!).and_raise(
          Onetime::LimitExceeded.new(
            'Too many login attempts. Please try again later.',
            retry_after: 1800,
            max_attempts: 5,
          ),
        )
      end

      it 'raises LimitExceeded from raise_concerns before evaluating credentials' do
        expect(logic).not_to receive(:record_failed_login_attempt!)
        expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
      end
    end

    context 'on a failed credential attempt' do
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
end
