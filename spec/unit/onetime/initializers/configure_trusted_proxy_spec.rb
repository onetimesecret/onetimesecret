# spec/unit/onetime/initializers/configure_trusted_proxy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'ipaddr'

RSpec.describe Onetime::Initializers::ConfigureTrustedProxy do
  let(:instance) { described_class.new }
  let(:context) { {} }
  let(:logger) { instance_double('Logger', debug: nil, warn: nil) }

  before do
    allow(instance).to receive(:app_logger).and_return(logger)
    # Capture originals before each test
    @saved_forwarded_priority = Rack::Request.forwarded_priority
    @saved_ip_filter = Rack::Request.ip_filter
    @saved_ip_method = Rack::Request.instance_method(:ip)
  end

  after do
    # Restore Rack::Request state after each test
    Rack::Request.forwarded_priority = @saved_forwarded_priority
    Rack::Request.ip_filter = @saved_ip_filter
    # Restore original #ip method
    original_method = @saved_ip_method
    Rack::Request.class_eval do
      define_method(:ip, original_method)
    end
  end

  describe '#execute' do
    # ==========================================================================
    # Priority 1: Disabled state (enabled: false)
    # ==========================================================================
    context 'when enabled: false (new config structure)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => false
              }
            }
          }
        })
      end

      it 'sets forwarded_priority to empty array' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([])
      end

      it 'logs that proxy is disabled' do
        instance.execute(context)
        expect(logger).to have_received(:debug).with(/Trusted proxy disabled/)
      end

      it 'does not modify ip_filter' do
        original_filter = Rack::Request.ip_filter
        instance.execute(context)
        expect(Rack::Request.ip_filter).to eq(original_filter)
      end
    end

    # ==========================================================================
    # Priority 1: Legacy config fallback (trusted_proxy_depth)
    # ==========================================================================
    context 'legacy config: trusted_proxy_depth = 0' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 0
          }
        })
      end

      it 'treats depth=0 as disabled' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([])
      end
    end

    context 'legacy config: trusted_proxy_depth > 0' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 1
          }
        })
      end

      it 'enables filter mode' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
      end

      it 'uses X-Forwarded-For header by default' do
        instance.execute(context)
        expect(logger).to have_received(:debug).with(/header=X-Forwarded-For/)
      end
    end

    context 'legacy config: with trusted_ip_header' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 1,
            'trusted_ip_header' => 'Forwarded'
          }
        })
      end

      it 'respects trusted_ip_header setting' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([:forwarded])
      end
    end

    context 'legacy config: with trusted_proxy_cidrs' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 1,
            'trusted_proxy_cidrs' => ['203.0.113.0/24']
          }
        })
      end

      it 'configures custom CIDRs' do
        instance.execute(context)
        filter = Rack::Request.ip_filter
        expect(filter.call('203.0.113.50')).to be true
      end
    end

    context 'when site config is missing entirely' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'defaults to disabled without error' do
        expect { instance.execute(context) }.not_to raise_error
        expect(Rack::Request.forwarded_priority).to eq([])
      end
    end

    # ==========================================================================
    # Priority 1: Filter mode (enabled: true, mode: filter)
    # ==========================================================================
    context 'when enabled: true, mode: filter' do
      context 'with default header' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter'
                }
              }
            }
          })
        end

        it 'sets forwarded_priority to [:x_forwarded]' do
          instance.execute(context)
          expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
        end

        it 'logs mode and header' do
          instance.execute(context)
          expect(logger).to have_received(:debug).with(/mode=filter.*header=X-Forwarded-For/)
        end
      end

      context 'with header: X-Forwarded-For' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'header' => 'X-Forwarded-For'
                }
              }
            }
          })
        end

        it 'sets forwarded_priority to [:x_forwarded]' do
          instance.execute(context)
          expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
        end
      end

      context 'with header: Forwarded (RFC 7239)' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'header' => 'Forwarded'
                }
              }
            }
          })
        end

        it 'sets forwarded_priority to [:forwarded]' do
          instance.execute(context)
          expect(Rack::Request.forwarded_priority).to eq([:forwarded])
        end
      end

      context 'with header: Both' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'header' => 'Both'
                }
              }
            }
          })
        end

        it 'sets forwarded_priority to [:forwarded, :x_forwarded]' do
          instance.execute(context)
          expect(Rack::Request.forwarded_priority).to eq([:forwarded, :x_forwarded])
        end
      end

      context 'with unknown header value' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'header' => 'Unknown-Header'
                }
              }
            }
          })
        end

        it 'falls back to [:x_forwarded]' do
          instance.execute(context)
          expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
        end
      end

      context 'with cidrs configured' do
        let(:custom_cidrs) { ['203.0.113.0/24', '198.51.100.0/24'] }

        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'cidrs' => custom_cidrs
                }
              }
            }
          })
        end

        it 'extends ip_filter to trust custom CIDR ranges' do
          instance.execute(context)
          filter = Rack::Request.ip_filter

          expect(filter.call('203.0.113.50')).to be true
          expect(filter.call('198.51.100.1')).to be true
        end

        it 'still trusts RFC1918 addresses via default filter' do
          instance.execute(context)
          filter = Rack::Request.ip_filter

          expect(filter.call('10.0.0.1')).to be true
          expect(filter.call('192.168.1.1')).to be true
          expect(filter.call('172.16.0.1')).to be true
        end

        it 'does not trust arbitrary public IPs' do
          instance.execute(context)
          filter = Rack::Request.ip_filter

          expect(filter.call('8.8.8.8')).to be false
          expect(filter.call('1.2.3.4')).to be false
        end

        it 'logs cidrs count' do
          instance.execute(context)
          expect(logger).to have_received(:debug).with(/cidrs=2/)
        end
      end

      context 'with IPv6 CIDRs' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'filter',
                  'cidrs' => ['2001:db8::/32']
                }
              }
            }
          })
        end

        it 'trusts IPv6 addresses within configured CIDR' do
          instance.execute(context)
          filter = Rack::Request.ip_filter

          expect(filter.call('2001:db8::1')).to be true
          expect(filter.call('2001:db8:abcd::1')).to be true
        end

        it 'does not trust IPv6 addresses outside configured CIDR' do
          instance.execute(context)
          filter = Rack::Request.ip_filter

          expect(filter.call('2001:db9::1')).to be false
        end
      end
    end

    # ==========================================================================
    # Priority 1: Depth mode (enabled: true, mode: depth)
    # ==========================================================================
    context 'when enabled: true, mode: depth' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'depth',
                'depth' => 2,
                'header' => 'X-Forwarded-For'
              }
            }
          }
        })
      end

      it 'sets forwarded_priority to empty array (disables Rack parsing)' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([])
      end

      it 'overrides Rack::Request#ip' do
        # Stub ClientIpHelpers to verify it gets called
        allow(Onetime::ClientIpHelpers).to receive(:extract).and_return('1.2.3.4')

        instance.execute(context)

        # Create a mock request and verify #ip uses ClientIpHelpers
        env = { 'REMOTE_ADDR' => '127.0.0.1' }
        request = Rack::Request.new(env)
        result = request.ip

        expect(Onetime::ClientIpHelpers).to have_received(:extract).with(
          env,
          depth: 2,
          header: 'X-Forwarded-For'
        )
        expect(result).to eq('1.2.3.4')
      end

      it 'logs mode, depth, and header' do
        instance.execute(context)
        expect(logger).to have_received(:debug).with(/mode=depth.*depth=2.*header=X-Forwarded-For/)
      end

      context 'with depth clamped to valid range' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'depth',
                  'depth' => 100 # exceeds max of 10
                }
              }
            }
          })
        end

        it 'clamps depth to maximum of 10' do
          allow(Onetime::ClientIpHelpers).to receive(:extract).and_return('1.2.3.4')
          instance.execute(context)

          env = { 'REMOTE_ADDR' => '127.0.0.1' }
          Rack::Request.new(env).ip

          expect(Onetime::ClientIpHelpers).to have_received(:extract).with(
            env,
            depth: 10,
            header: 'X-Forwarded-For'
          )
        end
      end

      context 'with depth of 0 or negative (clamped to 1)' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'depth',
                  'depth' => 0
                }
              }
            }
          })
        end

        it 'clamps depth to minimum of 1' do
          allow(Onetime::ClientIpHelpers).to receive(:extract).and_return('1.2.3.4')
          instance.execute(context)

          env = { 'REMOTE_ADDR' => '127.0.0.1' }
          Rack::Request.new(env).ip

          expect(Onetime::ClientIpHelpers).to have_received(:extract).with(
            env,
            depth: 1,
            header: 'X-Forwarded-For'
          )
        end
      end
    end

    # ==========================================================================
    # Priority 1: Invalid CIDR handling
    # ==========================================================================
    context 'with invalid CIDR in cidrs array' do
      let(:custom_cidrs) { ['203.0.113.0/24', 'invalid-cidr', '198.51.100.0/24'] }

      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'filter',
                'cidrs' => custom_cidrs
              }
            }
          }
        })
      end

      it 'logs warning for invalid CIDR' do
        instance.execute(context)
        expect(logger).to have_received(:warn).with(/Invalid trusted_proxy_cidr 'invalid-cidr'/)
      end

      it 'continues processing valid CIDRs' do
        instance.execute(context)
        filter = Rack::Request.ip_filter

        expect(filter.call('203.0.113.50')).to be true
        expect(filter.call('198.51.100.1')).to be true
      end

      it 'does not raise error' do
        expect { instance.execute(context) }.not_to raise_error
      end
    end

    context 'with all invalid CIDRs' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'filter',
                'cidrs' => ['not-a-cidr', 'also-invalid']
              }
            }
          }
        })
      end

      it 'logs warning for each invalid CIDR' do
        instance.execute(context)
        expect(logger).to have_received(:warn).twice
      end

      it 'does not modify ip_filter when all CIDRs are invalid' do
        original_filter = Rack::Request.ip_filter
        instance.execute(context)
        # Verify default behavior unchanged
        expect(Rack::Request.ip_filter.call('10.0.0.1')).to eq(original_filter.call('10.0.0.1'))
      end
    end

    context 'with empty cidrs array' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'filter',
                'cidrs' => []
              }
            }
          }
        })
      end

      it 'does not modify ip_filter' do
        original_filter = Rack::Request.ip_filter
        instance.execute(context)
        expect(Rack::Request.ip_filter).to eq(original_filter)
      end

      it 'logs cidrs=0' do
        instance.execute(context)
        expect(logger).to have_received(:debug).with(/cidrs=0/)
      end
    end

    # ==========================================================================
    # Edge case: ip_filter handles malformed IP input
    # ==========================================================================
    context 'ip_filter handles malformed IP input' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'filter',
                'cidrs' => ['203.0.113.0/24']
              }
            }
          }
        })
      end

      it 'returns false for malformed IP strings without raising' do
        instance.execute(context)
        filter = Rack::Request.ip_filter

        # Malformed IPs from attacker-controlled headers should not crash
        expect(filter.call('not-an-ip')).to be false
        expect(filter.call('')).to be false
        expect(filter.call('256.256.256.256')).to be false
      end
    end
  end

  describe 'class attributes' do
    it 'provides :trusted_proxy' do
      expect(described_class.provides).to eq([:trusted_proxy])
    end

    it 'has default phase :preload' do
      expect(described_class.phase).to eq(:preload)
    end
  end
end
