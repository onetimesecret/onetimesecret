# spec/unit/onetime/middleware/entitlement_preview_context_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/entitlement_preview_context'

# Unit tests for the entitlement preview context middleware (ADR-020).
#
# The middleware copies the session's preview keys into the Fiber-local
# consulted by the entitlement/limit chokepoints, and clears it in ensure.
# Correctness of the clear is what prevents preview state from bleeding
# across requests on the same fiber.
RSpec.describe Onetime::Middleware::EntitlementPreviewContext do
  let(:observed) { {} }

  let(:downstream) do
    lambda do |_env|
      observed[:context] = Onetime::EntitlementPreview.context
      [200, { 'content-type' => 'application/json' }, ['{}']]
    end
  end

  let(:middleware) { described_class.new(downstream) }

  def env_with_session(session)
    { 'rack.session' => session }
  end

  after { Onetime::EntitlementPreview.clear }

  describe 'context population' do
    it 'stashes the session preview keys for the duration of the request' do
      env = env_with_session(
        entitlement_preview_planid: 'identity_v1',
        entitlement_preview_grants_key: 'session:abc:entitlement_preview_grants',
        entitlement_preview_revokes_key: 'session:abc:entitlement_preview_revokes',
      )

      status, = middleware.call(env)

      expect(status).to eq(200)
      expect(observed[:context]).to eq(
        planid: 'identity_v1',
        grants_key: 'session:abc:entitlement_preview_grants',
        revokes_key: 'session:abc:entitlement_preview_revokes',
      )
    end

    it 'stashes a planid-only context when the session lacks reconciliation keys' do
      env = env_with_session(entitlement_preview_planid: 'identity_v1')

      middleware.call(env)

      expect(observed[:context]).to eq(planid: 'identity_v1', grants_key: nil, revokes_key: nil)
    end

    it 'sets no context when the session has no preview keys' do
      middleware.call(env_with_session({}))

      expect(observed[:context]).to be_nil
    end

    it 'sets no context when the preview keys are empty strings' do
      env = env_with_session(
        entitlement_preview_planid: '',
        entitlement_preview_grants_key: '',
        entitlement_preview_revokes_key: '',
      )

      middleware.call(env)

      expect(observed[:context]).to be_nil
    end

    it 'sets no context on a sessionless env' do
      middleware.call({})

      expect(observed[:context]).to be_nil
    end
  end

  describe 'clearing discipline' do
    it 'clears the Fiber-local after the request completes' do
      env = env_with_session(entitlement_preview_planid: 'identity_v1')

      middleware.call(env)

      expect(Onetime::EntitlementPreview.context).to be_nil
    end

    it 'clears the Fiber-local even when the app raises' do
      raising_app        = ->(_env) { raise 'boom' }
      raising_middleware = described_class.new(raising_app)
      env                = env_with_session(entitlement_preview_planid: 'identity_v1')

      expect { raising_middleware.call(env) }.to raise_error('boom')
      expect(Onetime::EntitlementPreview.context).to be_nil
    end

    it 'clears state leaked by a previous request before running the app' do
      Onetime::EntitlementPreview.set(planid: 'leaked_plan', grants_key: nil, revokes_key: nil)

      middleware.call({})

      expect(observed[:context]).to be_nil
    end

    it 'replaces leaked state with the current session state' do
      Onetime::EntitlementPreview.set(planid: 'leaked_plan', grants_key: nil, revokes_key: nil)
      env = env_with_session(entitlement_preview_planid: 'identity_v1')

      middleware.call(env)

      expect(observed[:context][:planid]).to eq('identity_v1')
    end
  end
end
