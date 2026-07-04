# apps/web/core/spec/middleware/error_handling_spec.rb
#
# frozen_string_literal: true

# Tests for Core::Middleware::ErrorHandling logging security.
#
# handle_unauthorized and handle_error both log request-derived data via
# http_logger directly -- not through Sentry, so Sentry's before_send URL
# scrubbing never runs on this path. Prior to this fix they logged req.url,
# the full URL including the query string, unredacted. A request that hits
# a 401/500 with a sensitive value in its query string (or, once an
# operator opts a field in via logging.http.allowed_error_fields, in its
# POST body) must never have that value written to the log line -- only
# the bare path, method, and ip.
#
# Run: pnpm run test:rspec apps/web/core/spec/middleware/error_handling_spec.rb

require 'spec_helper'
require 'rack/mock'
require_relative '../../middleware/error_handling'

RSpec.describe Core::Middleware::ErrorHandling do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(_env) { [200, {}, ['ok']] } }
  let(:env) do
    Rack::MockRequest.env_for(
      '/api/v3/secret/conceal?api_key=super-secret-value&utm_source=x',
      method: 'POST',
    )
  end
  # Onetime.get_logger('HTTP') (and thus #http_logger) does not reliably
  # return the same object identity on every call in a spec context that
  # hasn't gone through full app boot -- so stub #http_logger on the
  # middleware itself rather than grabbing one live instance and stubbing
  # that, which would silently miss the call made inside the method under
  # test.
  let(:logger_double) { double('HTTPLogger', info: nil, error: nil, debug: nil) }

  before do
    allow(middleware).to receive(:serve_vue_entry_point).and_return([401, {}, ['']])
    allow(middleware).to receive(:http_logger).and_return(logger_double)
    allow(OT).to receive(:d9s_enabled).and_return(false)
  end

  describe '#handle_unauthorized (private)' do
    let(:ex) { OT::Unauthorized.new('Not authorized') }

    it 'logs path/method/ip but never the query string or full URL' do
      captured = nil
      allow(logger_double).to receive(:info) do |_msg, payload|
        captured = payload
      end

      middleware.send(:handle_unauthorized, env, ex)

      expect(captured[:path]).to eq('/api/v3/secret/conceal')
      expect(captured[:method]).to eq('POST')
      expect(captured).not_to have_key(:url)

      serialized = captured.values.join(' ')
      expect(serialized).not_to include('api_key')
      expect(serialized).not_to include('super-secret-value')
    end
  end

  describe '#handle_error (private)' do
    let(:ex) { StandardError.new('boom') }

    it 'logs path/method/ip but never the query string or full URL' do
      captured = nil
      allow(logger_double).to receive(:error) do |_msg, payload|
        captured ||= payload
      end

      middleware.send(:handle_error, env, ex)

      expect(captured[:path]).to eq('/api/v3/secret/conceal')
      expect(captured[:method]).to eq('POST')
      expect(captured).not_to have_key(:url)

      serialized = captured.values.join(' ')
      expect(serialized).not_to include('api_key')
      expect(serialized).not_to include('super-secret-value')
    end
  end

  describe '#capture_error (private, Sentry path)' do
    let(:ex) { StandardError.new('boom') }
    let(:mock_scope) do
      scope = double('Sentry::Scope')
      allow(scope).to receive(:set_context)
      scope
    end

    before do
      # Minimal Sentry stand-in, matching the convention in
      # apps/api/v1/spec/controllers/helpers_sentry_spec.rb: only define the
      # constant if the real sentry-ruby gem isn't already loaded. Method
      # bodies are empty placeholders -- they exist only so the constant
      # responds to these names (needed for verified doubles); the actual
      # behavior always comes from the `allow(Sentry).to receive(...)`
      # stubs below, which apply unconditionally either way.
      unless defined?(Sentry)
        stub_const('Sentry', Module.new do
          def self.initialized?; end
          def self.with_scope; end
          def self.capture_exception(_error); end
        end)
      end

      allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
      allow(Sentry).to receive(:capture_exception)
    end

    it 'sets request context with path (never the query string), method, and ip' do
      expect(mock_scope).to receive(:set_context).with(
        'request',
        hash_including(path: '/api/v3/secret/conceal', method: 'POST'),
      )

      middleware.send(:capture_error, ex, env)
    end

    it 'never passes the query string into Sentry context' do
      captured_context = nil
      allow(mock_scope).to receive(:set_context) do |key, value|
        captured_context = value if key == 'request'
      end

      middleware.send(:capture_error, ex, env)

      expect(captured_context).not_to have_key(:url)
      serialized = captured_context.values.join(' ')
      expect(serialized).not_to include('api_key')
      expect(serialized).not_to include('super-secret-value')
    end
  end
end
