# spec/unit/onetime/application/otto_hooks_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../apps/web/billing/errors'

RSpec.describe Onetime::Application::OttoHooks do
  # Minimal host: OttoHooks is a mixin, so include it in a bare class.
  let(:host_class) { Class.new { include Onetime::Application::OttoHooks } }
  let(:host)       { host_class.new }

  # Trusted-proxy resolution is no longer wired onto the Otto router. It lives
  # entirely on the universal IPPrivacyMiddleware mount, configured once from
  # MiddlewareStack.ip_privacy_security_config — see middleware_stack_spec.rb.
  # OttoHooks therefore no longer touches add_trusted_proxy.

  describe '#configure_otto_request_hook error registrations' do
    # Spy router records every register_error_handler call so we can assert OUR
    # registrations and exercise the handler blocks without booting a full Otto
    # app. Only the methods configure_otto_request_hook touches are stubbed.
    let(:registered) { {} }
    let(:spy_router) do
      captured = registered
      Object.new.tap do |spy|
        spy.define_singleton_method(:register_request_helpers) { |*| }
        spy.define_singleton_method(:on_request_complete) { |*, &_blk| }
        spy.define_singleton_method(:register_error_handler) do |klass, status:, log_level:, &handler|
          captured[klass] = { status: status, log_level: log_level, handler: handler }
        end
      end
    end

    before do
      allow(Onetime).to receive(:debug?).and_return(false)
      host.configure_otto_request_hook(spy_router)
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
