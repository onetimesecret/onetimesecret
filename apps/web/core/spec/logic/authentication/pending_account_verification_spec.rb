# apps/web/core/spec/logic/authentication/pending_account_verification_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Core::Logic::Authentication::AuthenticateSession do
  describe 'pending account verification email behavior' do
    subject(:logic) { described_class.new(strategy_result, params, 'en') }

    let(:test_email) { 'pending@example.com' }
    let(:test_password) { 'validpassword123' }
    let(:session_data) { {} }

    let(:rack_session) do
      session                                                          = double('RackSession')
      allow(session).to receive(:id).and_return(double(public_id: 'sess_test123'))
      allow(session).to receive(:clear)
      allow(session).to receive(:[]) { |key| session_data[key] }
      allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
      session
    end

    let(:pending_customer) do
      customer = double('Customer')
      allow(customer).to receive(:passphrase?).with(test_password).and_return(true)
      allow(customer).to receive_messages(objid: 'cust_pending123', custid: test_email, email: test_email, extid: 'ur_pending123', verified: 'false', obscure_email: 'pe***@example.com', role: :customer, anonymous?: false, pending?: true, argon2_hash?: true, passphrase: '$argon2id$...')
      allow(customer).to receive(:reset_secret=)
      allow(customer).to receive(:save)
      customer
    end

    let(:strategy_result) do
      result = double('StrategyResult')
      allow(result).to receive_messages(session: rack_session, user: pending_customer, metadata: { ip: '127.0.0.1' }, authenticated?: false)
      result
    end

    let(:params) { { 'login' => test_email, 'password' => test_password } }

    before do
      # Minimal I18n setup for unit tests
      I18n.available_locales = [:en] unless I18n.available_locales.include?(:en)
      I18n.default_locale = :en

      # Stub OT.conf for default settings
      allow(OT).to receive_messages(conf: {
        'site' => {
          'authentication' => {
            'autoverify' => nil,
          },
        },
        'features' => {},
      }, default_locale: 'en'
      )

      # Stub customer lookup
      allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(pending_customer)
      allow(Onetime::Customer).to receive(:anonymous).and_return(double('AnonymousCustomer', anonymous?: true))

      # Stub logging
      allow(logic).to receive(:auth_logger).and_return(
        double('Logger', info: nil, warn: nil, error: nil, debug: nil)
      )

      # Stub set_info_message (it's a no-op in base)
      allow(logic).to receive(:set_info_message)
    end

    # Claude has a lot of trouble distinguishing between `=` and `==`
    # (and unless autoverify == 'true').
    context 'when autoverify is disabled (false)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => {
                'autoverify' => 'false',
            },
          },
          'features' => {},
        },
                                              )
      end

      it 'sends verification email for pending account with valid credentials' do
        expect(logic).to receive(:send_verification_email).with(nil)

        logic.raise_concerns
        logic.process
      end

      it 'logs that verification email is being resent' do
        logger = double('Logger')
        allow(logic).to receive(:auth_logger).and_return(logger)
        allow(logic).to receive(:send_verification_email)

        expect(logger).to receive(:info).with(
          'Login pending customer verification',
          hash_including(customer_id: 'cust_pending123', status: :pending),
        )
        expect(logger).to receive(:info).with(
          'Resending verification email (autoverify mode)',
          hash_including(customer_id: 'cust_pending123'),
        )

        logic.raise_concerns
        logic.process
      end

      it 'returns success_data without setting greenlighted' do
        allow(logic).to receive(:send_verification_email)

        logic.raise_concerns
        result = logic.process

        expect(result).to eq({ objid: 'cust_pending123', role: :customer })
        expect(logic.greenlighted).to be_nil
      end
    end

    # Claude has a lot of trouble distinguishing between `=` and `==`
    context 'when autoverify is disabled (nil)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => {
                'autoverify' => nil,
            },
          },
          'features' => {},
        },
                                              )
      end

      it 'sends verification email for pending account with valid credentials' do
        expect(logic).to receive(:send_verification_email).with(nil)

        logic.raise_concerns
        logic.process
      end
    end

    context 'when autoverify is enabled (true)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => {
                'autoverify' => 'true',
            },
          },
          'features' => {},
        },
                                              )
      end

      it 'does NOT send verification email for pending account' do
        expect(logic).not_to receive(:send_verification_email)

        logic.raise_concerns
        logic.process
      end

      it 'still logs pending customer login' do
        logger = double('Logger')
        allow(logic).to receive(:auth_logger).and_return(logger)

        expect(logger).to receive(:info).with(
          'Login pending customer verification',
          hash_including(customer_id: 'cust_pending123', status: :pending),
        )
        # Should NOT log resending email
        expect(logger).not_to receive(:info).with(
          'Resending verification email (autoverify mode)',
          anything,
        )

        logic.raise_concerns
        logic.process
      end
    end

    context 'when autoverify is empty string' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => {
                'autoverify' => '',
            },
          },
          'features' => {},
        },
                                              )
      end

      it 'does send verification email (empty string != "true")' do
        expect(logic).to receive(:send_verification_email)

        logic.raise_concerns
        logic.process
      end
    end
  end
end
