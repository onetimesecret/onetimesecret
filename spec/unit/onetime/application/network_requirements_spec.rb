# spec/unit/onetime/application/network_requirements_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/network_requirements'

RSpec.describe Onetime::Application::NetworkRequirements do
  let(:router) { instance_double(Otto) }
  let(:logger) { instance_double(SemanticLogger::Logger, warn: nil) }
  let(:inner_handler) { ->(_env, *_args) { [200, {}, ['OK']] } }
  let(:factory) do
    captured = nil
    allow(router).to receive(:register_handler_wrapper) do |&block|
      captured = block
      router
    end
    described_class.register(router)
    captured
  end

  before do
    allow(Onetime).to receive(:get_logger).with('NetworkRequirements').and_return(logger)
  end

  def route(definition)
    Otto::RouteDefinition.new(:get, '/system/proxy-headers', definition)
  end

  it 'leaves routes without a network requirement unchanged' do
    definition = route('Object.to_s response=json')

    expect(factory.call(definition, inner_handler)).to equal(inner_handler)
  end

  it 'allows network=admin after both explicit admin gates admit the request' do
    definition = route('Object.to_s response=json network=admin')
    wrapper    = factory.call(definition, inner_handler)
    env        = {
      Onetime::Middleware::AdminNetworkIsolation::ROUTE_REQUIREMENT_ENV_KEY => true,
    }

    expect(wrapper.call(env).first).to eq(200)
  end

  it 'returns the route-shaped 404 when the admin network verdict is absent' do
    definition = route('Object.to_s response=json network=admin')
    wrapper    = factory.call(definition, inner_handler)

    expect(wrapper.call({})).to eq(
      [404, { 'Content-Type' => 'application/json' }, ['{"error":"Not Found"}']],
    )
  end

  it 'fails closed on an unknown network strategy' do
    definition = route('Object.to_s response=json network=unknown')

    expect { factory.call(definition, inner_handler) }
      .to raise_error(Otto::RouteDefinitionError, /Unknown network requirement "unknown"/)
  end

  it 'fails closed when a bare network option would otherwise be ignored by Otto' do
    definition = route('Object.to_s response=json network')

    expect { factory.call(definition, inner_handler) }
      .to raise_error(Otto::RouteDefinitionError, /expected network=value/)
  end

  it 'fails closed on a case-varied network option' do
    definition = route('Object.to_s response=json Network=admin')

    expect { factory.call(definition, inner_handler) }
      .to raise_error(Otto::RouteDefinitionError, /expected network=value/)
  end
end
