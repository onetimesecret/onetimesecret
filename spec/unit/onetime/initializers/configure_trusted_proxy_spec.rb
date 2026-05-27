# spec/unit/onetime/initializers/configure_trusted_proxy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'ipaddr'

RSpec.describe Onetime::Initializers::ConfigureTrustedProxy do
  let(:instance) { described_class.new }
  let(:context) { {} }
  let(:logger) { double('logger', debug: nil, info: nil, warn: nil) }

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

      it 'does not modify Rack::Request.forwarded_priority' do
        original_priority = Rack::Request.forwarded_priority
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
      end

      it 'does not log any debug messages' do
        instance.execute(context)
        expect(logger).not_to have_received(:debug)
      end

      it 'does not modify ip_filter' do
        original_filter = Rack::Request.ip_filter
        instance.execute(context)
        expect(Rack::Request.ip_filter).to eq(original_filter)
      end

      it 'preserves Rack defaults for request.ip resolution' do
        # Behavioral test: disabled mode should allow Rack's default IP resolution
        # Rack default: forwarded_priority = [:forwarded, :x_forwarded]
        instance.execute(context)

        # Verify Rack can still parse X-Forwarded-For with default settings
        env = {
          'REMOTE_ADDR' => '10.0.0.1',
          'HTTP_X_FORWARDED_FOR' => '203.0.113.50, 10.0.0.1'
        }
        request = Rack::Request.new(env)

        # With defaults, Rack trusts private IPs and returns first non-private
        # This verifies we haven't broken Rack's built-in proxy handling
        expect(request.ip).to eq('203.0.113.50')
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

      it 'treats depth=0 as disabled and preserves Rack defaults' do
        original_priority = Rack::Request.forwarded_priority
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
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

    context 'legacy config: with CIDRs + Forwarded header' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 1,
            'trusted_ip_header' => 'Forwarded',
            'trusted_proxy_cidrs' => ['203.0.113.0/24']
          }
        })
      end

      it 'uses Forwarded header priority' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([:forwarded])
      end

      it 'configures custom CIDRs' do
        instance.execute(context)
        filter = Rack::Request.ip_filter
        expect(filter.call('203.0.113.50')).to be true
      end
    end

    context 'legacy config: with invalid CIDRs' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'trusted_proxy_depth' => 1,
            'trusted_proxy_cidrs' => ['not-valid', '203.0.113.0/24']
          }
        })
      end

      it 'logs warning for invalid CIDR' do
        instance.execute(context)
        expect(logger).to have_received(:warn).with(/Invalid trusted_proxy_cidr 'not-valid'/)
      end

      it 'continues with valid CIDRs' do
        instance.execute(context)
        filter = Rack::Request.ip_filter
        expect(filter.call('203.0.113.50')).to be true
      end
    end

    context 'when site config is missing entirely' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'defaults to disabled and preserves Rack defaults' do
        original_priority = Rack::Request.forwarded_priority
        expect { instance.execute(context) }.not_to raise_error
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
      end

      it 'does not modify ip_filter' do
        original_filter = Rack::Request.ip_filter
        instance.execute(context)
        expect(Rack::Request.ip_filter).to eq(original_filter)
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
          expect(logger).to have_received(:info).with(
            'Configured trusted proxy filter mode', hash_including(header: 'X-Forwarded-For')
          )
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
          expect(logger).to have_received(:info).with(
            'Configured trusted proxy filter mode', hash_including(custom_cidrs: 2)
          )
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
        expect(logger).to have_received(:info).with(
          'Configured trusted proxy depth mode',
          hash_including(depth: 2, header: 'X-Forwarded-For')
        )
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

      context 'with header: Forwarded (RFC 7239)' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'depth',
                  'depth' => 1,
                  'header' => 'Forwarded'
                }
              }
            }
          })
        end

        it 'passes Forwarded header to ClientIpHelpers' do
          allow(Onetime::ClientIpHelpers).to receive(:extract).and_return('1.2.3.4')
          instance.execute(context)

          env = { 'REMOTE_ADDR' => '127.0.0.1' }
          Rack::Request.new(env).ip

          expect(Onetime::ClientIpHelpers).to have_received(:extract).with(
            env,
            depth: 1,
            header: 'Forwarded'
          )
        end
      end

      context 'with header: Both' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'network' => {
                'trusted_proxy' => {
                  'enabled' => true,
                  'mode' => 'depth',
                  'depth' => 1,
                  'header' => 'Both'
                }
              }
            }
          })
        end

        it 'passes Both header to ClientIpHelpers' do
          allow(Onetime::ClientIpHelpers).to receive(:extract).and_return('1.2.3.4')
          instance.execute(context)

          env = { 'REMOTE_ADDR' => '127.0.0.1' }
          Rack::Request.new(env).ip

          expect(Onetime::ClientIpHelpers).to have_received(:extract).with(
            env,
            depth: 1,
            header: 'Both'
          )
        end
      end
    end

    # ==========================================================================
    # Unrecognized mode falls through to filter
    # ==========================================================================
    context 'when mode is unrecognized' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'unknown-garbage'
              }
            }
          }
        })
      end

      it 'falls through to filter mode' do
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
      end

      it 'logs as filter mode' do
        instance.execute(context)
        expect(logger).to have_received(:info).with('Configured trusted proxy filter mode', anything)
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
        expect(logger).to have_received(:warn).with(
          'Invalid trusted_proxy CIDR; skipping', hash_including(cidr: 'invalid-cidr')
        )
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
        # Two per-CIDR warnings + one summary "no valid CIDRs registered" warning
        expect(logger).to have_received(:warn).with(
          'Invalid trusted_proxy CIDR; skipping', anything
        ).twice
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
        expect(logger).to have_received(:info).with(
          'Configured trusted proxy filter mode', hash_including(custom_cidrs: 0)
        )
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

    # ==========================================================================
    # Regression guards for config edge cases
    # ==========================================================================
    context 'when network key exists but trusted_proxy is nil' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => nil
            }
          }
        })
      end

      it 'treats nil config as disabled and preserves Rack defaults' do
        original_priority = Rack::Request.forwarded_priority
        expect { instance.execute(context) }.not_to raise_error
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
      end
    end

    context 'when network key exists but is empty hash' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {}
          }
        })
      end

      it 'treats missing trusted_proxy as disabled' do
        original_priority = Rack::Request.forwarded_priority
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
      end
    end

    context 'when enabled is truthy but not boolean true' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => 'yes',  # String, not boolean
                'mode' => 'filter'
              }
            }
          }
        })
      end

      it 'treats non-boolean truthy values as disabled (strict boolean check)' do
        original_priority = Rack::Request.forwarded_priority
        instance.execute(context)
        expect(Rack::Request.forwarded_priority).to eq(original_priority)
      end
    end
  end

  # ============================================================================
  # Integration test: initializer + middleware chain behavior
  # ============================================================================
  describe 'integration: middleware chain IP resolution' do
    let(:instance) { described_class.new }
    let(:context) { {} }
    let(:logger) { double('logger', debug: nil, info: nil, warn: nil) }

    before do
      allow(instance).to receive(:app_logger).and_return(logger)
      @saved_forwarded_priority = Rack::Request.forwarded_priority
      @saved_ip_filter = Rack::Request.ip_filter
      @saved_ip_method = Rack::Request.instance_method(:ip)
    end

    after do
      Rack::Request.forwarded_priority = @saved_forwarded_priority
      Rack::Request.ip_filter = @saved_ip_filter
      original_method = @saved_ip_method
      Rack::Request.class_eval do
        define_method(:ip, original_method)
      end
    end

    context 'filter mode with custom CIDRs' do
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
        instance.execute(context)
      end

      it 'resolves client IP through trusted proxy chain' do
        # Simulates: client 198.51.100.50 -> CDN 203.0.113.10 -> app
        env = {
          'REMOTE_ADDR' => '203.0.113.10',
          'HTTP_X_FORWARDED_FOR' => '198.51.100.50, 203.0.113.10'
        }
        request = Rack::Request.new(env)

        # 203.0.113.10 is trusted (custom CIDR), so Rack returns 198.51.100.50
        expect(request.ip).to eq('198.51.100.50')
      end

      it 'stops at untrusted proxy' do
        # Simulates: client -> untrusted proxy 8.8.8.8 -> trusted proxy -> app
        env = {
          'REMOTE_ADDR' => '10.0.0.1',
          'HTTP_X_FORWARDED_FOR' => '1.1.1.1, 8.8.8.8, 10.0.0.1'
        }
        request = Rack::Request.new(env)

        # 10.0.0.1 is trusted (RFC1918), 8.8.8.8 is not, so returns 8.8.8.8
        expect(request.ip).to eq('8.8.8.8')
      end
    end

    context 'depth mode with ClientIpHelpers' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'network' => {
              'trusted_proxy' => {
                'enabled' => true,
                'mode' => 'depth',
                'depth' => 2
              }
            }
          }
        })
        instance.execute(context)
      end

      it 'uses ClientIpHelpers for IP extraction' do
        env = {
          'REMOTE_ADDR' => '10.0.0.1',
          'HTTP_X_FORWARDED_FOR' => '1.1.1.1, 2.2.2.2, 10.0.0.1'
        }
        request = Rack::Request.new(env)

        # depth=2 means skip 2 rightmost entries from XFF chain
        # Chain: ['1.1.1.1', '2.2.2.2', '10.0.0.1'] (length=3)
        # forwarded[0...-2].last -> ['1.1.1.1'].last -> '1.1.1.1'
        expect(request.ip).to eq('1.1.1.1')
      end
    end

    context 'disabled mode preserves standard Rack behavior' do
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
        instance.execute(context)
      end

      it 'uses Rack default IP resolution' do
        env = {
          'REMOTE_ADDR' => '10.0.0.1',
          'HTTP_X_FORWARDED_FOR' => '203.0.113.50, 10.0.0.1'
        }
        request = Rack::Request.new(env)

        # Rack defaults trust RFC1918, returns first non-private IP
        expect(request.ip).to eq('203.0.113.50')
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
