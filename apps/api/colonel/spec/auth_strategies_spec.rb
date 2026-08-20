# apps/api/colonel/spec/auth_strategies_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/auth_strategies'

RSpec.describe ColonelAPI::AuthStrategies::SessionAuthStrategy do
  subject(:strategy) { described_class.new }

  let(:env) do
    {
      'PATH_INFO' => '/system/proxy-headers',
      'REMOTE_ADDR' => '10.0.0.4',
      'HTTP_HOST' => 'origin.example.test',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.9',
      'HTTP_APX_INCOMING_HOST' => 'tenant.example.test',
      'HTTP_X_OTS_PROXY_DEBUG_PEER' => '198.51.100.10',
      'otto.client_ip' => '203.0.113.0',
      'otto.via_trusted_proxy' => true,
      Rack::DetectHost.result_field_name => 'tenant.example.test',
    }
  end

  describe '#build_metadata' do
    it 'captures only the fixed proxy fields for the diagnostic route' do
      metadata = strategy.send(:build_metadata, env)

      expect(metadata[:proxy_header_debug]).to eq(
        caddy_received: {
          'x-ots-proxy-debug-peer' => '198.51.100.10',
          'x-ots-proxy-debug-host' => nil,
          'x-ots-proxy-debug-received-x-forwarded-for' => nil,
          'x-ots-proxy-debug-received-forwarded' => nil,
          'x-ots-proxy-debug-received-apx-incoming-host' => nil,
        },
        rack: {
          remote_addr: '10.0.0.4',
          client_ip: '203.0.113.0',
          via_trusted_proxy: true,
          detected_host: 'tenant.example.test',
        },
        request_headers: {
          'host' => 'origin.example.test',
          'x-forwarded-for' => '203.0.113.9',
          'x-forwarded-host' => nil,
          'x-forwarded-proto' => nil,
          'forwarded' => nil,
          'apx-incoming-host' => 'tenant.example.test',
        },
      )
    end

    it 'reads detected_host through the configurable result field name' do
      original = Rack::DetectHost.result_field_name
      begin
        Rack::DetectHost.result_field_name = 'custom.detected_host'
        env.delete(original)
        env['custom.detected_host'] = 'renamed.example.test'

        metadata = strategy.send(:build_metadata, env)

        expect(metadata[:proxy_header_debug][:rack][:detected_host]).to eq('renamed.example.test')
      ensure
        Rack::DetectHost.result_field_name = original
      end
    end

    it 'does not add proxy metadata to other Colonel requests' do
      env['PATH_INFO'] = '/system/database'

      expect(strategy.send(:build_metadata, env)).not_to have_key(:proxy_header_debug)
    end
  end
end
