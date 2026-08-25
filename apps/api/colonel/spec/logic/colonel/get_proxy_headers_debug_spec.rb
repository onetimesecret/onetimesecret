# apps/api/colonel/spec/logic/colonel/get_proxy_headers_debug_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.describe ColonelAPI::Logic::Colonel::GetProxyHeadersDebug do
  let(:colonel) do
    instance_double(Onetime::Customer, role: 'colonel', verified?: true, anonymous?: false)
  end
  let(:payload) do
    {
      caddy_received: { 'x-ots-proxy-debug-peer' => '198.51.100.10' },
      rack: {
        remote_addr: '10.0.0.4',
        client_ip: '203.0.113.0',
        via_trusted_proxy: true,
        detected_host: 'tenant.example.test',
      },
      request_headers: {
        'x-forwarded-for' => '203.0.113.9',
        'apx-incoming-host' => 'tenant.example.test',
      },
    }
  end
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: { proxy_header_debug: payload },
    )
  end

  it 'returns the route-specific proxy metadata unchanged' do
    logic = described_class.new(strategy_result, {})

    logic.raise_concerns

    expect(logic.process).to eq(payload)
  end

  it 'returns an empty object if no diagnostic metadata was captured' do
    allow(strategy_result).to receive(:metadata).and_return({})
    logic = described_class.new(strategy_result, {})

    expect(logic.process).to eq({})
  end
end
