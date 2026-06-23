# spec/unit/onetime/application/otto_hooks_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../apps/web/billing/errors'

RSpec.describe Onetime::Application::OttoHooks do
  # Minimal host: OttoHooks is a mixin, so include it in a bare class.
  let(:host_class) { Class.new { include Onetime::Application::OttoHooks } }
  let(:host)       { host_class.new }

  # Stand-in for the Otto router. We only assert OUR wiring (the gate + the
  # ranges handed over); Otto's own client_ipaddress / secure? resolution from
  # that trust list is covered by the gem.
  let(:router) { instance_double(Otto) }

  describe '#configure_otto_trusted_proxies' do
    context 'when trusted_proxy is enabled' do
      before do
        allow(Onetime::Application::MiddlewareStack)
          .to receive(:trusted_proxy_enabled?).and_return(true)
      end

      it 'hands the router the shared private-proxy ranges' do
        expect(router).to receive(:add_trusted_proxy)
          .with(Onetime::Application::MiddlewareStack::PRIVATE_PROXY_RANGES)

        host.configure_otto_trusted_proxies(router)
      end
    end

    context 'when trusted_proxy is disabled' do
      before do
        allow(Onetime::Application::MiddlewareStack)
          .to receive(:trusted_proxy_enabled?).and_return(false)
      end

      it 'leaves the router trust list empty (direct-connection mode)' do
        expect(router).not_to receive(:add_trusted_proxy)

        host.configure_otto_trusted_proxies(router)
      end
    end
  end

  describe '#configure_otto_request_hook error registrations' do
    # Spy router records every register_error_handler call so we can assert OUR
    # registrations and exercise the handler blocks without booting a full Otto
    # app. Only the methods configure_otto_request_hook touches are stubbed.
    let(:registered) { {} }
    let(:spy_router) do
      captured = registered
      Object.new.tap do |spy|
        spy.define_singleton_method(:register_request_helpers) { |*| }
        spy.define_singleton_method(:add_trusted_proxy) { |*| }
        spy.define_singleton_method(:on_request_complete) { |*, &_blk| }
        spy.define_singleton_method(:register_error_handler) do |klass, status:, log_level:, &handler|
          captured[klass] = { status: status, log_level: log_level, handler: handler }
        end
      end
    end

    before do
      allow(Onetime::Application::MiddlewareStack)
        .to receive(:trusted_proxy_enabled?).and_return(false)
      allow(Onetime).to receive(:debug?).and_return(false)
      host.configure_otto_request_hook(spy_router)
    end

    describe 'error correlation (request_id + error_type)' do
      let(:request_id) { 'req-abc-123' }

      # Minimal stand-in for the Otto/Rack request: handlers only touch #env.
      def req_with(env)
        Object.new.tap do |o|
          captured = env
          o.define_singleton_method(:env) { captured }
        end
      end

      it 'echoes the request_id into a typed 404 (RecordNotFound) body' do
        env   = { 'HTTP_X_REQUEST_ID' => request_id }
        entry = registered[Onetime::RecordNotFound]

        body = entry[:handler].call(Onetime::RecordNotFound.new('nope'), req_with(env))

        expect(body[:request_id]).to eq(request_id)
        expect(body[:error_type]).to eq('RecordNotFound')
      end

      it 'stashes the error_type into env so RequestLogger can name what failed' do
        env   = { 'HTTP_X_REQUEST_ID' => request_id }
        entry = registered[Onetime::RecordNotFound]

        entry[:handler].call(Onetime::RecordNotFound.new('nope'), req_with(env))

        expect(env['otto.error_type']).to eq('RecordNotFound')
      end

      it 'omits request_id from the body when the request carries none' do
        entry = registered[Onetime::RecordNotFound]

        body = entry[:handler].call(Onetime::RecordNotFound.new('nope'), req_with({}))

        expect(body).not_to have_key(:request_id)
        expect(body[:error_type]).to eq('RecordNotFound')
      end

      it 'is nil-safe when no request is supplied (handler unit-test path)' do
        entry = registered[Onetime::RecordNotFound]

        expect { entry[:handler].call(Onetime::RecordNotFound.new('nope'), nil) }
          .not_to raise_error
      end

      it 'also decorates the lazy-registered Billing::CircuitOpenError body' do
        env   = { 'HTTP_X_REQUEST_ID' => request_id }
        entry = registered['Billing::CircuitOpenError']

        body = entry[:handler].call(
          Billing::CircuitOpenError.new('Stripe circuit breaker is open', retry_after: 9),
          req_with(env),
        )

        expect(body[:request_id]).to eq(request_id)
        expect(body[:retry_after]).to eq(9)
        expect(env['otto.error_type']).to eq('BillingServiceUnavailable')
      end

      # FormError#to_h compacts away a nil error_type, so the body carries none.
      # The request log should still name the failure via the exception class.
      it 'falls back to the exception class name for the log when the body omits error_type' do
        env   = { 'HTTP_X_REQUEST_ID' => request_id }
        entry = registered[Onetime::FormError]

        body = entry[:handler].call(Onetime::FormError.new('You did not provide anything'), req_with(env))

        expect(body).not_to have_key(:error_type)        # body contract unchanged
        expect(env['otto.error_type']).to eq('FormError') # log still names it
        expect(body[:request_id]).to eq(request_id)
      end

      it "prefers the FormError's own error_type over the class-name fallback" do
        env   = { 'HTTP_X_REQUEST_ID' => request_id }
        entry = registered[Onetime::FormError]

        body = entry[:handler].call(
          Onetime::FormError.new('Emails differ', error_type: 'email_mismatch'),
          req_with(env),
        )

        expect(body[:error_type]).to eq('email_mismatch')
        expect(env['otto.error_type']).to eq('email_mismatch')
      end
    end

    describe 'Billing::CircuitOpenError (Stripe breaker open)' do
      let(:entry) { registered['Billing::CircuitOpenError'] }

      it 'maps to 503 at log_level :warn' do
        expect(entry).not_to be_nil
        expect(entry[:status]).to eq(503)
        expect(entry[:log_level]).to eq(:warn)
      end

      it 'is registered by string name so it is harmless without the billing app' do
        expect(registered.keys).to include('Billing::CircuitOpenError')
      end

      it 'returns a generic body that never leaks the breaker failure count or upstream provider' do
        # The real error message embeds an internal failure count and "Stripe".
        error = Billing::CircuitOpenError.new(
          'Stripe circuit breaker is open (7 failures). Retry after 42s.',
          retry_after: 42,
        )

        body = entry[:handler].call(error, nil)

        expect(body[:error_type]).to eq('BillingServiceUnavailable')
        expect(body[:error]).not_to match(/Stripe|circuit|failure/i)
        expect(body[:retry_after]).to eq(42)
        expect(body.values_at(:error, :error_type, :retry_after)).to eq(body.values)
      end

      it 'omits retry_after when the breaker carries none' do
        error = Billing::CircuitOpenError.new('Stripe circuit breaker is open')

        body = entry[:handler].call(error, nil)

        expect(body).not_to have_key(:retry_after)
      end
    end
  end
end
