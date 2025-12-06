# apps/web/core/spec/controllers/authentication_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Core::Controllers::Authentication do
  subject(:controller) { described_class.new(req, res) }

  let(:session_data) { {} }
  let(:session_id) { double('SessionId', public_id: 'sess_abc123') }
  let(:rack_session) do
    # Create a proper double that supports both Hash-like access and session methods
    session                                                          = double('RackSession')
    allow(session).to receive(:id).and_return(session_id)
    allow(session).to receive(:clear) { session_data.clear }
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    session
  end
  let(:session_options) { {} }
  let(:env) do
    {
      'rack.session' => rack_session,
      'rack.session.options' => session_options,
      'HTTP_ACCEPT' => 'text/html',
      'REMOTE_ADDR' => '127.0.0.1',
    }
  end
  let(:req) do
    request = double('Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:ip).and_return('127.0.0.1')
    allow(request).to receive(:locale).and_return('en')
    request
  end
  let(:res) do
    response = double('Response')
    allow(response).to receive(:do_not_cache!)
    allow(response).to receive(:redirect)
    allow(response).to receive(:app_path) { |path| path }
    allow(response).to receive(:status=)
    response
  end

  before do
    # Stub logging methods
    allow(controller).to receive(:auth_logger).and_return(double('Logger', debug: nil, info: nil))
  end

  describe '#logout' do
    context 'with authenticated session' do
      let(:session_data) do
        {
          'external_id' => 'ur_abc123',
          'email' => 'test@example.com',
          'role' => 'customer',
          'authenticated' => true,
          'authenticated_at' => Time.now.to_i,
        }
      end

      it 'clears the session data' do
        expect(rack_session).to receive(:clear)
        controller.logout
      end

      it 'sets cache headers to prevent caching' do
        expect(res).to receive(:do_not_cache!)
        controller.logout
      end

      it 'sets session renew option to regenerate session ID' do
        controller.logout
        expect(session_options[:renew]).to be true
      end

      it 'logs session destruction initiation' do
        logger = double('Logger')
        allow(controller).to receive(:auth_logger).and_return(logger)

        expect(logger).to receive(:debug).with(
          'Session destruction initiated',
          hash_including(customer_id: 'ur_abc123', ip: '127.0.0.1'),
        )
        expect(logger).to receive(:info).with(
          'Session destroyed',
          hash_including(customer_id: 'ur_abc123', ip: '127.0.0.1'),
        )

        controller.logout
      end

      context 'with HTML request' do
        let(:env) { super().merge('HTTP_ACCEPT' => 'text/html') }

        it 'redirects to home page' do
          expect(res).to receive(:redirect).with('/')
          controller.logout
        end

        it 'sets success message in session' do
          controller.logout
          expect(session_data['success_message']).to eq('You have been logged out')
        end
      end

      context 'with JSON request' do
        let(:env) { super().merge('HTTP_ACCEPT' => 'application/json') }

        it 'returns JSON success response' do
          expect(res).to receive(:status=).with(200)
          result = controller.logout
          expect(result).to eq({ success: 'You have been logged out' })
        end

        it 'does not redirect' do
          expect(res).not_to receive(:redirect)
          controller.logout
        end
      end
    end

    context 'without authenticated session (idempotent)' do
      let(:session_data) { {} }

      it 'succeeds without error' do
        expect { controller.logout }.not_to raise_error
      end

      it 'still clears the session' do
        expect(rack_session).to receive(:clear)
        controller.logout
      end

      it 'still sets renew option' do
        controller.logout
        expect(session_options[:renew]).to be true
      end

      it 'logs with nil customer_id' do
        logger = double('Logger')
        allow(controller).to receive(:auth_logger).and_return(logger)

        expect(logger).to receive(:debug).with(
          'Session destruction initiated',
          hash_including(customer_id: nil),
        )
        expect(logger).to receive(:info).with(
          'Session destroyed',
          hash_including(customer_id: nil),
        )

        controller.logout
      end
    end

    context 'when rack.session.options is not available' do
      let(:env) { super().tap { |e| e.delete('rack.session.options') } }

      it 'does not raise error' do
        expect { controller.logout }.not_to raise_error
      end

      it 'still clears session' do
        expect(rack_session).to receive(:clear)
        controller.logout
      end
    end

    context 'when session.id raises error' do
      before do
        allow(rack_session).to receive(:id).and_raise(StandardError.new('no session id'))
      end

      it 'handles the error gracefully and continues' do
        expect { controller.logout }.not_to raise_error
      end
    end
  end

  describe 'security considerations' do
    let(:session_data) do
      {
        'external_id' => 'ur_secret123',
        'email' => 'sensitive@example.com',
        'authenticated' => true,
      }
    end

    it 'captures session info before clearing for accurate logging' do
      logger = double('Logger')
      allow(controller).to receive(:auth_logger).and_return(logger)

      # The customer_id should be captured BEFORE clear is called
      expect(logger).to receive(:debug).with(
        'Session destruction initiated',
        hash_including(customer_id: 'ur_secret123'),
      )
      expect(logger).to receive(:info)

      controller.logout
    end

    it 'ensures session is cleared even if logging fails' do
      logger = double('Logger')
      allow(controller).to receive(:auth_logger).and_return(logger)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info).and_raise(StandardError.new('logging failed'))

      # Session should still be cleared before the error propagates
      expect(rack_session).to receive(:clear).ordered

      expect { controller.logout }.to raise_error(StandardError, 'logging failed')
    end

    it 'regenerates session ID to prevent session fixation' do
      controller.logout
      expect(session_options[:renew]).to be true
    end
  end
end
