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
    allow(Onetime::Customer).to receive(:anonymous).and_return(anonymous_customer)

    # Stub logging on the class so it works before subject is created
    allow_any_instance_of(described_class).to receive(:auth_logger).and_return(mock_logger)
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
    # Note: The base class (Logic::Base) always ensures @cust is not nil by
    # setting it to Onetime::Customer.anonymous if strategy_result.user is nil.
    # Therefore, raise_concerns in this class is effectively a no-op since it
    # only acts when @cust.nil?. The actual authentication error handling
    # happens in #process via the success? check.

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

      it 'does not raise (error handling is in #process)' do
        # raise_concerns doesn't handle password failures - that's done in process
        expect { logic.raise_concerns }.not_to raise_error
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
            expect(logic).to receive(:set_info_message).with(a_string_matching(/cust_test123/))
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
          # Role is managed via CLI (bin/ots role promote) and stored on customer record
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
