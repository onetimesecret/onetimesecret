# apps/web/core/spec/controllers/welcome_spec.rb
#
# frozen_string_literal: true

# Tests for Core::Controllers::Welcome#welcome endpoint guard
#
# The guard handles missing `checkout` param:
# 1. Missing checkout + custom domain -> Sentry error + silent redirect to /
# 2. Missing checkout + canonical domain -> Sentry error + flash message + redirect to /
# 3. Valid checkout -> normal flow (existing logic)
#
# Run: pnpm run test:rspec apps/web/core/spec/controllers/welcome_spec.rb

require 'spec_helper'
require 'sentry-ruby'

# Load the welcome controller
require_relative '../../controllers/welcome'

# Load billing logic (required for valid checkout tests)
require_relative '../../../billing/logic/welcome'

RSpec.describe Core::Controllers::Welcome do
  subject(:controller) { described_class.new(req, res) }

  let(:session_data) { {} }
  let(:rack_session) do
    session = double('RackSession')
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    session
  end

  let(:strategy_metadata) { { domain_strategy: domain_strategy } }
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: rack_session,
      user: nil,
      authenticated?: false,
      metadata: strategy_metadata
    )
  end

  let(:params) { {} }
  let(:env) do
    {
      'rack.session' => rack_session,
      'otto.strategy_result' => strategy_result,
      'HTTP_ACCEPT' => 'text/html',
      'HTTP_REFERER' => 'https://example.com/pricing',
      'QUERY_STRING' => '',
    }
  end

  let(:req) do
    request = double('Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:params).and_return(params)
    allow(request).to receive(:path).and_return('/welcome')
    allow(request).to receive(:query_string).and_return(env['QUERY_STRING'])
    allow(request).to receive(:locale).and_return('en')
    allow(request).to receive(:app_path) { |path| path }
    request
  end

  let(:redirect_location) { nil }
  let(:res) do
    response = double('Response')
    allow(response).to receive(:redirect) { |location| @redirect_location = location }
    allow(response).to receive(:body=)
    allow(response).to receive(:status=)
    response
  end

  # Stub Sentry to track calls
  let(:sentry_messages) { [] }
  let(:sentry_scope) do
    scope = double('SentryScope')
    allow(scope).to receive(:set_context)
    scope
  end

  before do
    # Stub OT.d9s_enabled to enable Sentry capture
    allow(OT).to receive(:d9s_enabled).and_return(true)

    # Track Sentry.capture_message calls
    allow(Sentry).to receive(:capture_message) do |message, level:, &block|
      sentry_messages << { message: message, level: level }
      block.call(sentry_scope) if block
    end

    # Stub logging methods
    allow(controller).to receive(:http_logger).and_return(double('Logger', debug: nil, info: nil, warn: nil, error: nil))
  end

  describe '#welcome' do
    context 'when checkout param is missing' do
      let(:params) { {} }

      context 'on canonical domain' do
        let(:domain_strategy) { :canonical }

        it 'captures Sentry error message' do
          controller.welcome

          expect(sentry_messages.length).to eq(1)
          expect(sentry_messages.first[:message]).to eq('Welcome page accessed without checkout param')
          expect(sentry_messages.first[:level]).to eq(:error)
        end

        it 'sets error flash message' do
          controller.welcome

          expect(session_data['error_message']).to eq(
            'It looks like you were redirected here but something went wrong. Please contact support.'
          )
        end

        it 'redirects to root path' do
          controller.welcome

          expect(@redirect_location).to eq('/')
        end

        it 'includes domain_strategy in Sentry context' do
          controller.welcome

          expect(sentry_scope).to have_received(:set_context).with(
            'request',
            hash_including(domain_strategy: :canonical)
          )
        end
      end

      context 'on custom domain' do
        let(:domain_strategy) { :custom }

        it 'captures Sentry error message' do
          controller.welcome

          expect(sentry_messages.length).to eq(1)
          expect(sentry_messages.first[:message]).to eq('Welcome page accessed without checkout param')
          expect(sentry_messages.first[:level]).to eq(:error)
        end

        it 'does NOT set flash message (silent redirect)' do
          controller.welcome

          expect(session_data['error_message']).to be_nil
        end

        it 'redirects to root path' do
          controller.welcome

          expect(@redirect_location).to eq('/')
        end

        it 'includes domain_strategy in Sentry context' do
          controller.welcome

          expect(sentry_scope).to have_received(:set_context).with(
            'request',
            hash_including(domain_strategy: :custom)
          )
        end
      end

      context 'on subdomain' do
        let(:domain_strategy) { :subdomain }

        it 'captures Sentry error message' do
          controller.welcome

          expect(sentry_messages.length).to eq(1)
          expect(sentry_messages.first[:message]).to eq('Welcome page accessed without checkout param')
        end

        it 'sets flash message (subdomain is still our support)' do
          controller.welcome

          # Subdomain users contact OTS support, so show the message
          expect(session_data['error_message']).to eq(
            'It looks like you were redirected here but something went wrong. Please contact support.'
          )
        end

        it 'redirects to root path' do
          controller.welcome

          expect(@redirect_location).to eq('/')
        end
      end

      context 'when domain_strategy is nil' do
        let(:domain_strategy) { nil }

        it 'captures Sentry error message' do
          controller.welcome

          expect(sentry_messages.length).to eq(1)
        end

        it 'sets flash message (nil strategy defaults to showing support message)' do
          controller.welcome

          expect(session_data['error_message']).to eq(
            'It looks like you were redirected here but something went wrong. Please contact support.'
          )
        end

        it 'redirects to root path' do
          controller.welcome

          expect(@redirect_location).to eq('/')
        end
      end

      context 'with referrer and query string in Sentry context' do
        let(:domain_strategy) { :canonical }

        before do
          env['HTTP_REFERER'] = 'https://stripe.com/checkout'
          env['QUERY_STRING'] = 'utm_source=marketing'
          allow(req).to receive(:query_string).and_return('utm_source=marketing')
        end

        it 'includes referrer in Sentry context' do
          controller.welcome

          expect(sentry_scope).to have_received(:set_context).with(
            'request',
            hash_including(referrer: 'https://stripe.com/checkout')
          )
        end

        it 'includes query_string in Sentry context' do
          controller.welcome

          expect(sentry_scope).to have_received(:set_context).with(
            'request',
            hash_including(query_string: 'utm_source=marketing')
          )
        end
      end

      context 'when Sentry is disabled' do
        before do
          allow(OT).to receive(:d9s_enabled).and_return(false)
        end

        let(:domain_strategy) { :canonical }

        it 'does not call Sentry.capture_message' do
          expect(Sentry).not_to receive(:capture_message)

          controller.welcome
        end

        it 'still sets flash message on canonical domain' do
          controller.welcome

          expect(session_data['error_message']).not_to be_nil
          expect(session_data['error_message']).to include('something went wrong')
        end

        it 'still redirects to root' do
          controller.welcome

          expect(@redirect_location).to eq('/')
        end
      end
    end

    context 'when checkout param is present' do
      let(:domain_strategy) { :canonical }
      let(:checkout_session_id) { 'cs_test_abc123xyz' }
      let(:params) { { 'checkout' => checkout_session_id } }

      let(:mock_checkout_session) do
        double(
          'StripeCheckoutSession',
          id: checkout_session_id,
          customer: 'cus_test_123',
          customer_details: double(email: 'test@example.com'),
          subscription: double(id: 'sub_test_123')
        )
      end

      let(:mock_logic) do
        logic = double('FromStripePaymentLink')
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        logic
      end

      before do
        # Stub the billing logic class
        allow(Billing::Logic::Welcome::FromStripePaymentLink).to receive(:new).and_return(mock_logic)
      end

      it 'does NOT capture Sentry message' do
        expect(Sentry).not_to receive(:capture_message)

        controller.welcome
      end

      it 'does NOT set flash message' do
        controller.welcome

        expect(session_data['error_message']).to be_nil
      end

      it 'does NOT redirect to root (processes checkout instead)' do
        controller.welcome

        # With valid checkout, redirect should be to /account, not /
        expect(@redirect_location).to eq('/account')
      end

      it 'instantiates the billing logic with correct parameters' do
        expect(Billing::Logic::Welcome::FromStripePaymentLink).to receive(:new).with(
          strategy_result,
          params,
          'en'
        ).and_return(mock_logic)

        controller.welcome
      end

      it 'calls raise_concerns and process on the logic' do
        expect(mock_logic).to receive(:raise_concerns).ordered
        expect(mock_logic).to receive(:process).ordered

        controller.welcome
      end
    end

    context 'when checkout param is empty string' do
      let(:domain_strategy) { :canonical }
      let(:params) { { 'checkout' => '' } }

      # NOTE: Empty string is truthy in Ruby, so `unless req.params['checkout']`
      # will pass an empty string through to the billing logic, where it will
      # fail validation. This documents the current behavior - if we want to
      # treat empty string as missing, the guard would need to be:
      # `unless req.params['checkout'].to_s.strip.present?`
      it 'passes empty string to billing logic (NOT treated as missing)' do
        # The billing logic will raise an error for invalid checkout session
        # We're just documenting that empty string gets past the guard
        mock_logic = double('FromStripePaymentLink')
        allow(mock_logic).to receive(:raise_concerns).and_raise(OT::FormError.new('No Stripe checkout_session_id'))
        allow(Billing::Logic::Welcome::FromStripePaymentLink).to receive(:new).and_return(mock_logic)

        expect { controller.welcome }.to raise_error(OT::FormError, /No Stripe checkout_session_id/)
      end
    end
  end
end
