# spec/unit/onetime/logic/route_param_spec.rb
#
# frozen_string_literal: true
#
# Run: pnpm run test:rspec spec/unit/onetime/logic/route_param_spec.rb
#
# Otto >= 2.12 (delano/otto#285) hands a Logic class the router's path
# captures as `route_params:` when its initialize declares the keyword.
# Onetime::Logic::Base declares it for every subclass, and #route_param is
# how a Logic class reads a path value by name instead of fishing it out of
# the shared params namespace (where a query string, form field or JSON body
# key of the same name used to be able to replace it).

require 'spec_helper'
require 'otto'
require 'onetime/logic/base'

RSpec.describe Onetime::Logic::Base, '#route_param' do
  def logic_with(params:, route_params:)
    described_class.allocate.tap do |logic|
      logic.instance_variable_set(:@params, params)
      logic.instance_variable_set(:@route_params, route_params)
    end
  end

  it 'declares the route_params keyword Otto looks for on initialize' do
    parameters = described_class.instance_method(:initialize).parameters
    expect(parameters).to include([:key, :route_params])
  end

  it 'returns the path capture when the router supplied one' do
    logic = logic_with(
      params: { 'identifier' => 'from-the-body' },
      route_params: { 'identifier' => 'from-the-path' },
    )
    expect(logic.route_param('identifier')).to eq('from-the-path')
  end

  it 'prefers the capture even when params disagree by symbol key' do
    logic = logic_with(
      params: { 'identifier' => 'from-the-body' },
      route_params: { identifier: 'from-the-path' },
    )
    expect(logic.route_param(:identifier)).to eq('from-the-path')
  end

  it "reads Otto's indifferent capture hash by string or symbol" do
    captures = Otto::Static.indifferent_params({ 'identifier' => 'abc123' })
    logic    = logic_with(params: {}, route_params: captures)

    expect(logic.route_param('identifier')).to eq('abc123')
    expect(logic.route_param(:identifier)).to eq('abc123')
  end

  it 'falls back to params when the class was built without the router' do
    logic = logic_with(params: { 'identifier' => 'by-hand' }, route_params: {})
    expect(logic.route_param('identifier')).to eq('by-hand')
  end

  it 'returns nil, not an error, when params are nil and nothing was captured' do
    logic = logic_with(params: nil, route_params: {})
    expect(logic.route_param('identifier')).to be_nil
  end
end
