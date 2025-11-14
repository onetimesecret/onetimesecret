# spec/unit/apps/web/core/middleware/request_setup_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'i18n'

RSpec.describe Core::Middleware::RequestSetup do
  include Rack::Test::Methods

  let(:app) do
    lambda { |env| [200, { 'content-type' => 'text/plain' }, ['OK']] }
  end

  let(:middleware) { described_class.new(app) }

  before(:each) do
    I18n.backend.reload!
    I18n.locale = :en
  end

  describe 'locale handling' do
    context 'when otto.locale is set in env' do
      it 'sets I18n.locale to match otto.locale' do
        env = Rack::MockRequest.env_for('/', {})
        env['otto.locale'] = 'fr'

        middleware.call(env)

        expect(I18n.locale).to eq(:fr)
      end

      it 'converts locale to symbol' do
        env = Rack::MockRequest.env_for('/', {})
        env['otto.locale'] = 'de'

        middleware.call(env)

        expect(I18n.locale).to be_a(Symbol)
        expect(I18n.locale).to eq(:de)
      end

      it 'handles different locale values' do
        locales = %w[en fr de es]

        locales.each do |locale|
          env = Rack::MockRequest.env_for('/', {})
          env['otto.locale'] = locale

          middleware.call(env)

          expect(I18n.locale).to eq(locale.to_sym)
        end
      end
    end

    context 'when otto.locale is not set' do
      it 'does not crash' do
        env = Rack::MockRequest.env_for('/', {})
        # No otto.locale set

        expect { middleware.call(env) }.not_to raise_error
      end

      it 'leaves I18n.locale unchanged' do
        original_locale = I18n.locale
        env = Rack::MockRequest.env_for('/', {})

        middleware.call(env)

        # Should not be modified
        expect(I18n.locale).to eq(original_locale)
      end
    end
  end

  describe 'nonce generation' do
    it 'generates a nonce for CSP headers' do
      env = Rack::MockRequest.env_for('/', {})

      middleware.call(env)

      expect(env['onetime.nonce']).to be_a(String)
      expect(env['onetime.nonce']).not_to be_empty
    end

    it 'generates unique nonces for each request' do
      env1 = Rack::MockRequest.env_for('/', {})
      env2 = Rack::MockRequest.env_for('/', {})

      middleware.call(env1)
      middleware.call(env2)

      expect(env1['onetime.nonce']).not_to eq(env2['onetime.nonce'])
    end

    it 'generates base64-encoded nonces' do
      env = Rack::MockRequest.env_for('/', {})

      middleware.call(env)

      nonce = env['onetime.nonce']
      # Base64 pattern: alphanumeric, +, /, =
      expect(nonce).to match(/\A[A-Za-z0-9+\/=]+\z/)
    end
  end

  describe 'content-type handling' do
    it 'sets default content-type when not set' do
      app_without_content_type = lambda { |env| [200, {}, ['OK']] }
      middleware_instance = described_class.new(app_without_content_type)
      env = Rack::MockRequest.env_for('/', {})

      status, headers, body = middleware_instance.call(env)

      expect(headers['content-type']).to eq('text/html; charset=utf-8')
    end

    it 'does not override existing content-type' do
      app_with_content_type = lambda do |env|
        [200, { 'content-type' => 'application/json' }, ['{}'']]
      end
      middleware_instance = described_class.new(app_with_content_type)
      env = Rack::MockRequest.env_for('/', {})

      status, headers, body = middleware_instance.call(env)

      expect(headers['content-type']).to eq('application/json')
    end

    it 'uses custom default content-type when configured' do
      app_plain = lambda { |env| [200, {}, ['OK']] }
      middleware_instance = described_class.new(
        app_plain,
        default_content_type: 'text/plain'
      )
      env = Rack::MockRequest.env_for('/', {})

      status, headers, body = middleware_instance.call(env)

      expect(headers['content-type']).to eq('text/plain')
    end
  end

  describe 'request flow' do
    it 'calls the downstream app' do
      env = Rack::MockRequest.env_for('/', {})
      app_spy = double('app')
      expect(app_spy).to receive(:call).with(env).and_return([200, {}, ['OK']])

      middleware_instance = described_class.new(app_spy)
      middleware_instance.call(env)
    end

    it 'returns the app response' do
      response = [201, { 'X-Custom' => 'header' }, ['Created']]
      custom_app = lambda { |env| response }
      middleware_instance = described_class.new(custom_app)
      env = Rack::MockRequest.env_for('/', {})

      result = middleware_instance.call(env)

      expect(result[0]).to eq(201)
      expect(result[1]['X-Custom']).to eq('header')
    end
  end

  describe 'integration with Otto::Locale::Middleware' do
    it 'works with locale set by Otto middleware' do
      # Simulate Otto::Locale::Middleware setting the locale
      env = Rack::MockRequest.env_for('/', {})
      env['otto.locale'] = 'es'

      middleware.call(env)

      # Verify I18n.locale is synchronized
      expect(I18n.locale).to eq(:es)
    end

    it 'processes request even if Otto locale is invalid' do
      env = Rack::MockRequest.env_for('/', {})
      env['otto.locale'] = 'invalid_locale'

      # Should not crash
      expect { middleware.call(env) }.not_to raise_error
    end
  end
end
