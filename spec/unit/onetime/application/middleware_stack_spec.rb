# spec/unit/onetime/application/middleware_stack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Application::MiddlewareStack do
  describe '.ip_privacy_security_config' do
    subject(:config) { described_class.ip_privacy_security_config }

    # otto 2.10 pins Rack::Request.forwarded_priority from the header set here
    # and registers the config process-wide; spec_helper resets that registry
    # after every example so the Forwarded/Both examples below cannot conflict
    # with the X-Forwarded-For ones.

    def stub_conf(trusted_proxy, geo = {})
      allow(OT).to receive(:conf).and_return(
        'site' => { 'network' => { 'trusted_proxy' => trusted_proxy, 'geo' => geo } },
      )
    end

    context 'when trusted_proxy is absent' do
      before { allow(OT).to receive(:conf).and_return({}) }

      it 'still masks private/localhost IPs while trusting no proxy hop' do
        # The removed per-router enable_full_ip_privacy! calls ran
        # unconditionally, so direct-connect deployments must keep masking
        # private addresses rather than leaking them unmasked.
        aggregate_failures do
          expect(config).to be_a(Otto::Security::Config)
          expect(config.ip_privacy_config.mask_private_ips).to be(true)
          expect(config.trusted_proxy?('10.0.0.1')).to be(false)
          expect(config.trusted_proxy_depth_mode?).to be(false)
        end
      end
    end

    context 'when trusted_proxy is disabled' do
      before { stub_conf('enabled' => false) }

      let(:client_forwarded_env) do
        Rack::MockRequest.env_for(
          'http://onetime.test/',
          'HTTP_FORWARDED' => 'host=evil.example.com;proto=https',
        )
      end

      it 'still masks private/localhost IPs while trusting no proxy hop' do
        aggregate_failures do
          expect(config).to be_a(Otto::Security::Config)
          expect(config.ip_privacy_config.mask_private_ips).to be(true)
          expect(config.trusted_proxy?('10.0.0.1')).to be(false)
        end
      end

      it 'pins Rack to the X-Forwarded-* family so a client Forwarded header cannot set request.host' do
        Rack::Request.forwarded_priority = [:forwarded, :x_forwarded]

        config
        request = Rack::Request.new(client_forwarded_env)
        aggregate_failures do
          expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
          expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
          expect(request.host).to eq('onetime.test')
          expect(request.scheme).to eq('http')
        end
      end

      it 'ignores a stale Forwarded header setting: it is documented as inert while disabled' do
        stub_conf('enabled' => false, 'mode' => 'depth', 'depth' => 1, 'header' => 'Forwarded')
        aggregate_failures do
          expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
          expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
        end
      end
    end

    context 'when trusted_proxy is enabled' do
      before { stub_conf('enabled' => true) }

      it 'returns an Otto security config' do
        expect(config).to be_a(Otto::Security::Config)
      end

      it 'trusts RFC1918 proxy hops' do
        aggregate_failures do
          expect(config.trusted_proxy?('10.244.10.0')).to be(true)
          expect(config.trusted_proxy?('192.168.1.1')).to be(true)
          expect(config.trusted_proxy?('172.16.0.1')).to be(true)
          expect(config.trusted_proxy?('172.31.255.255')).to be(true)
          expect(config.trusted_proxy?('127.0.0.1')).to be(true)
          # IPv4 link-local (169.254/16)
          expect(config.trusted_proxy?('169.254.1.1')).to be(true)
        end
      end

      it 'trusts IPv6 loopback, ULA, and link-local proxy hops' do
        aggregate_failures do
          expect(config.trusted_proxy?('::1')).to be(true)            # loopback
          expect(config.trusted_proxy?('fc00::1')).to be(true)        # ULA
          expect(config.trusted_proxy?('fd12:3456::1')).to be(true)   # ULA
          expect(config.trusted_proxy?('fe80::1')).to be(true)        # link-local
          expect(config.trusted_proxy?('feb0::1')).to be(true)        # link-local /10 upper bound
        end
      end

      it 'does not trust public client addresses' do
        aggregate_failures do
          expect(config.trusted_proxy?('203.0.113.42')).to be(false)
          expect(config.trusted_proxy?('198.51.100.7')).to be(false)
          # 172.32 is outside the RFC1918 172.16/12 block
          expect(config.trusted_proxy?('172.32.0.1')).to be(false)
          # Global-unicast IPv6 (2000::/3) must not match the fc/fd/fe branches
          expect(config.trusted_proxy?('2001:db8::1')).to be(false)
          # fec0::/10 (deprecated site-local) is outside fe80::/10 link-local
          expect(config.trusted_proxy?('fec0::1')).to be(false)
        end
      end

      it 'enables full IP masking (private/localhost masked too)' do
        # One universal mount replaces the per-router enable_full_ip_privacy!
        # calls; the config must carry mask_private_ips so private addresses are
        # masked, not exempted.
        expect(config.ip_privacy_config.mask_private_ips).to be(true)
      end

      it 'uses CIDR-walk by default (no depth mode)' do
        expect(config.trusted_proxy_depth_mode?).to be(false)
      end
    end

    context 'when filter mode declares additional public CIDRs' do
      before do
        stub_conf(
          'enabled' => true,
          'mode' => 'filter',
          'cidrs' => ['203.0.113.0/24', '2001:db8::/32'],
        )
      end

      it 'trusts the configured public CIDRs in addition to RFC1918' do
        aggregate_failures do
          # configured public IPv4 CIDR
          expect(config.trusted_proxy?('203.0.113.42')).to be(true)
          # still trusts RFC1918
          expect(config.trusted_proxy?('10.244.10.0')).to be(true)
          # configured public IPv6 CIDR
          expect(config.trusted_proxy?('2001:db8::1')).to be(true)
          # an address outside both stays untrusted
          expect(config.trusted_proxy?('198.51.100.7')).to be(false)
        end
      end

      it 'ignores blank CIDR entries without raising' do
        stub_conf(
          'enabled' => true,
          'mode' => 'filter',
          'cidrs' => ['', '  ', '203.0.113.0/24'],
        )
        expect { config }.not_to raise_error
        expect(config.trusted_proxy?('203.0.113.42')).to be(true)
      end
    end

    context 'when depth mode is configured' do
      before do
        stub_conf(
          'enabled' => true,
          'mode' => 'depth',
          'depth' => 2,
        )
      end

      it 'maps Onetime depth N DIRECTLY to otto trusted_proxy_depth N' do
        # No +1: otto's chain[-(N+1)] index already accounts for the appended
        # REMOTE_ADDR, so depth N = "N proxy hops counting the connecting peer"
        # — the operator-facing meaning of `depth: N`. The former +1 remap
        # made honest documented-topology requests resolve the proxy address
        # (short-chain fallback) and let one forged leftmost XFF entry win.
        expect(config.trusted_proxy_depth).to eq(2)
      end

      it 'activates count-based depth mode' do
        expect(config.trusted_proxy_depth_mode?).to be(true)
      end

      it 'does not also register CIDR proxies (mutually exclusive in otto)' do
        expect(config.trusted_proxies).to be_empty
      end

      it 'clamps Onetime depth to 1..10' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 50)
        expect(config.trusted_proxy_depth).to eq(10) # clamp(1,10) => 10
      end

      it 'treats a zero depth as the minimum (1)' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 0)
        expect(config.trusted_proxy_depth).to eq(1) # clamp(1,10) => 1
      end

      it 'treats an absent depth as the minimum (1)' do
        stub_conf('enabled' => true, 'mode' => 'depth')
        expect(config.trusted_proxy_depth).to eq(1) # nil.to_i => 0, clamp => 1
      end
    end

    # The mode reaches this method through .trusted_proxy_mode, so the branch
    # below must follow the CANONICALIZED, VALIDATED value — not the operator's
    # raw string. Before #4087 `Depth` fell through the `== 'depth'` equality
    # test into the filter branch while the boot log announced `mode=Depth`.
    context 'when the mode needs canonicalizing or rejecting (#4087)' do
      before do
        allow(OT).to receive(:lw)
        described_class.reset_warn_once!
      end

      after { described_class.reset_warn_once! }

      it 'honours a mixed-case Depth as depth mode' do
        stub_conf('enabled' => true, 'mode' => 'Depth', 'depth' => 3)
        aggregate_failures do
          expect(config.trusted_proxy_depth_mode?).to be(true)
          expect(config.trusted_proxy_depth).to eq(3)
          # depth and CIDRs are mutually exclusive in otto
          expect(config.trusted_proxies).to be_empty
        end
      end

      it 'runs the filter/CIDR branch for an unrecognized mode' do
        # The fallback is the SAFER mode: each hop is authenticated against the
        # trusted-proxy CIDRs rather than counted. Asserting the CIDRs are
        # actually registered (not just "depth is off") is what distinguishes
        # the filter branch from a stack that trusts nothing at all.
        stub_conf('enabled' => true, 'mode' => 'dept', 'depth' => 3)
        aggregate_failures do
          expect(config.trusted_proxy_depth_mode?).to be(false)
          expect(config.trusted_proxy?('10.0.0.1')).to be(true)
          expect(config.trusted_proxies).not_to be_empty
        end
      end
    end

    context 'when geo.header meets depth mode (#4068)' do
      # otto 2.8 raises on trusted_proxy_depth + geo_header, so the translator
      # skips the setting under depth. Skipping silently left the operator with
      # a configured-looking header, no boot signal, and '**' on every request.
      before do
        allow(OT).to receive(:lw)
        described_class.reset_warn_once!
      end

      after { described_class.reset_warn_once! }

      it 'does not pass geo_header to otto (would be a boot failure)' do
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        aggregate_failures do
          expect { config }.not_to raise_error
          expect(config.ip_privacy_config.geo_header).to be_nil
        end
      end

      it 'warns that the configured header is ignored, naming it and the alternative' do
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        config
        expect(OT).to have_received(:lw).with(/X-Country.*IGNORED.*db_path/m)
      end

      it 'warns that country resolves to ** when depth mode has no geo source at all' do
        # No operator header AND no local DB: the built-in vendor headers are
        # equally inert under depth, so geo is on but resolves nothing.
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1)
        config
        expect(OT).to have_received(:lw).with(/depth.*db_path/m)
      end

      it 'stays quiet in depth mode when a local geo DB is configured' do
        # Stub the otto-side load so this asserts the warning logic, not
        # MaxMind file handling — the earlier version swallowed every
        # exception, which would have passed even if the DB path were never
        # honored at all.
        # any_instance: the Otto::Privacy::Config is built inside
        # Otto::Security::Config.new, so there is no seam to inject a double.
        allow_any_instance_of(Otto::Privacy::Config).to receive(:load_geo_database!) # rubocop:disable RSpec/AnyInstance
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'db_path' => '/geo.mmdb')
        aggregate_failures do
          expect(config.ip_privacy_config.geo_db_path).to eq('/geo.mmdb')
          expect(OT).not_to have_received(:lw)
        end
      end

      it 'warns once per process, not once per Application subclass' do
        # Seven Application subclasses each build a stack through this method;
        # the operator should read the finding once.
        stub_conf({ 'enabled' => true, 'mode' => 'depth', 'depth' => 1 }, 'header' => 'X-Country')
        3.times { described_class.ip_privacy_security_config }
        expect(OT).to have_received(:lw).once
      end

      it 'passes geo_header through in filter mode without warning' do
        stub_conf({ 'enabled' => true, 'mode' => 'filter' }, 'header' => 'X-Country')
        aggregate_failures do
          # otto normalizes the setting to its rack env key on assignment.
          expect(config.ip_privacy_config.geo_header).to eq('HTTP_X_COUNTRY')
          expect(OT).not_to have_received(:lw)
        end
      end
    end

    context 'when a forwarded header is configured (otto#150)' do
      it 'wires RFC 7239 Forwarded through to otto in depth mode' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Forwarded')
        expect(config.trusted_proxy_header).to eq('Forwarded')
      end

      it 'pins Rack to the family depth mode names (otto 2.10)' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Forwarded')
        config
        expect(Rack::Request.forwarded_priority).to eq([:forwarded])
      end

      it 'pins Rack to X-Forwarded-* in filter mode' do
        stub_conf('enabled' => true, 'mode' => 'filter')
        config
        expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
      end

      it 'rejects Forwarded in filter mode against the operator-facing config keys' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => 'forwarded')
        expect { config }.to raise_error(ArgumentError, /trusted_proxy\.header.*requires mode=depth/)
      end

      it 'names the misspelled mode the operator wrote, not just the fallback' do
        stub_conf('enabled' => true, 'mode' => 'dept', 'header' => 'Forwarded')
        expect { config }.to raise_error(ArgumentError, /"dept" is not a recognized value/)
      end

      it 'rejects Both in filter mode' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => 'Both')
        expect { config }.to raise_error(ArgumentError, /requires mode=depth/)
      end

      it 'wires Both through to otto in depth mode' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Both')
        expect(config.trusted_proxy_header).to eq('Both')
      end

      it 'canonicalizes a case-insensitive header value' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'forwarded')
        expect(config.trusted_proxy_header).to eq('Forwarded')
      end

      it 'defaults to X-Forwarded-For when the header is absent' do
        stub_conf('enabled' => true, 'mode' => 'filter')
        expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
      end

      it 'treats a blank header as the default (no raise)' do
        stub_conf('enabled' => true, 'mode' => 'filter', 'header' => '  ')
        expect { config }.not_to raise_error
        expect(config.trusted_proxy_header).to eq('X-Forwarded-For')
      end

      it 'fails the boot loudly on an unrecognized header (no silent mis-resolution)' do
        stub_conf('enabled' => true, 'mode' => 'depth', 'depth' => 1, 'header' => 'Banana')
        expect { config }.to raise_error(ArgumentError, /trusted_proxy_header/)
      end
    end

    describe '.trusted_proxy_enabled?' do
      def stub_conf(trusted_proxy)
        allow(OT).to receive(:conf).and_return(
          'site' => { 'network' => { 'trusted_proxy' => trusted_proxy } },
        )
      end

      it 'is false when the trusted_proxy section is absent' do
        allow(OT).to receive(:conf).and_return({})
        expect(described_class.trusted_proxy_enabled?).to be(false)
      end

      it 'is false when explicitly disabled' do
        stub_conf('enabled' => false)
        expect(described_class.trusted_proxy_enabled?).to be(false)
      end

      it 'is true only when explicitly enabled' do
        stub_conf('enabled' => true)
        expect(described_class.trusted_proxy_enabled?).to be(true)
      end
    end

    # #4087: the SINGLE Ruby reader for site.network.trusted_proxy.mode. Two
    # consumers depend on it agreeing with itself — .ip_privacy_security_config
    # branches on it to configure otto, and
    # AdminNetworkIsolation#trusted_proxy_posture prints it on the boot line
    # operators are told to read. They used to dig the config independently
    # with different expressions, which is how a deployment could run filter
    # while announcing `mode=Depth`.
    describe '.trusted_proxy_mode' do
      subject(:mode) { described_class.trusted_proxy_mode }

      def stub_mode(value)
        allow(OT).to receive(:conf).and_return(
          'site' => { 'network' => { 'trusted_proxy' => { 'enabled' => true, 'mode' => value } } },
        )
      end

      before do
        allow(OT).to receive(:lw)
        # The ledger is process-wide and every example here is about whether a
        # warning fired; without the reset the first example to warn is the
        # only one that can observe it and the rest pass or fail by run order.
        described_class.reset_warn_once!
      end

      after { described_class.reset_warn_once! }

      it 'never returns a value outside the known set' do
        # Pins the contract the two consumers rely on, against the constant
        # rather than restating the set.
        expect(described_class::TRUSTED_PROXY_MODES).to contain_exactly('filter', 'depth')
      end

      context 'with nothing configured' do
        it 'defaults to filter when the trusted_proxy section is absent' do
          allow(OT).to receive(:conf).and_return({})
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'defaults to filter when the key is absent from an enabled block' do
          allow(OT).to receive(:conf).and_return(
            'site' => { 'network' => { 'trusted_proxy' => { 'enabled' => true } } },
          )
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'defaults to filter for an explicit nil' do
          stub_mode(nil)
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'defaults to filter for an empty string, silently' do
          # Unset and blank are the same operator statement — "I did not
          # choose" — and must not produce a boot warning on a stock install.
          stub_mode('')
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'defaults to filter for a whitespace-only value' do
          stub_mode("  \t ")
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end
      end

      context 'with a recognized value' do
        it 'returns filter' do
          stub_mode('filter')
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'returns depth' do
          stub_mode('depth')
          aggregate_failures do
            expect(mode).to eq('depth')
            expect(OT).not_to have_received(:lw)
          end
        end

        it 'strips surrounding whitespace' do
          # OT.conf is also assembled programmatically (specs, embedders), so
          # the strip is not covered by YAML plain-scalar parsing alone.
          stub_mode('  depth  ')
          expect(mode).to eq('depth')
        end
      end

      # Downcase FIRST, then validate: `Depth` is the same setting written in a
      # different case, not a typo, and the sibling trusted_proxy.header value
      # is already canonicalized case-insensitively. The operator is still told
      # their value was rewritten, so the boot log and their config file can be
      # reconciled by eye.
      context 'with a mixed-case value' do
        it 'canonicalizes Depth to depth' do
          stub_mode('Depth')
          expect(mode).to eq('depth')
        end

        it 'canonicalizes DEPTH to depth' do
          stub_mode('DEPTH')
          expect(mode).to eq('depth')
        end

        it 'canonicalizes FILTER to filter' do
          stub_mode('FILTER')
          expect(mode).to eq('filter')
        end

        it 'warns that the value was canonicalized, naming both forms' do
          stub_mode('Depth')
          mode
          expect(OT).to have_received(:lw).with(/Depth/)
        end

        it 'does not call the canonicalized value unrecognized' do
          # A distinct warning from the unknown-value one: `Depth` IS honoured.
          # Telling the operator it is "not a recognized mode" while running
          # depth would be the same class of untrue boot line #4087 fixes.
          stub_mode('Depth')
          mode
          expect(OT).not_to have_received(:lw).with(/not a recognized mode/)
        end

        it 'warns once across repeated calls' do
          stub_mode('Depth')
          3.times { described_class.trusted_proxy_mode }
          expect(OT).to have_received(:lw).once
        end
      end

      # The behaviour-change claim is only true for values that canonicalize TO
      # depth: the old branch was an exact `== 'depth'` test, so every other
      # rewritten spelling ran filter before and runs filter now. Saying their
      # client IP resolution CHANGED is the same class of untrue boot line #4087
      # exists to fix, and sharing a warn_once tag with the real case would let a
      # cosmetic rewrite swallow the warning that matters.
      context 'when canonicalization does not change the effective mode' do
        it 'does not claim a behaviour change for FILTER' do
          stub_mode('FILTER')
          mode
          expect(OT).not_to have_received(:lw).with(/CHANGES how the client IP is resolved/)
        end

        it 'does not claim a behaviour change for padded filter' do
          stub_mode('  filter  ')
          mode
          expect(OT).not_to have_received(:lw).with(/CHANGES how the client IP is resolved/)
        end

        it 'still tells the operator the value was rewritten, naming both forms' do
          # Silence would leave the boot log and the config file irreconcilable
          # by eye — the point of warning at all.
          stub_mode('FILTER')
          mode
          expect(OT).to have_received(:lw).with(/FILTER.*"filter"/m)
        end

        it 'says client IP resolution is unchanged' do
          stub_mode('FILTER')
          mode
          expect(OT).to have_received(:lw).with(/client IP resolution is unchanged/)
        end

        it 'does not consume the behaviour-change warning for a later value' do
          # Each Application subclass builds its own stack and re-reads this;
          # one tag for both cases means a cosmetic FILTER rewrite in the first
          # stack silences the real Depth warning in the second.
          stub_mode('FILTER')
          mode
          stub_mode('Depth')
          described_class.trusted_proxy_mode
          expect(OT).to have_received(:lw).with(/CHANGES how the client IP is resolved/)
        end
      end

      # Whitespace was significant to the old exact `== 'depth'` match, so a
      # padded depth ran filter then and runs depth now — a behaviour change like
      # any other misspelling, not a cosmetic rewrite.
      context 'with a padded depth value' do
        it 'warns that the behaviour changed on upgrade' do
          stub_mode('  depth  ')
          mode
          expect(OT).to have_received(:lw).with(/CHANGES how the client IP is resolved/)
        end
      end

      # WARN, do not raise: the fallback is the safer mode and a log-adjacent
      # setting must never be the thing that fails a boot. Silence is the only
      # unacceptable option, since the operator asked for something the app is
      # not doing.
      context 'with an unrecognized value' do
        it 'falls back to filter for a near-miss typo' do
          stub_mode('dept')
          expect(mode).to eq('filter')
        end

        it 'falls back to filter for an unrelated word' do
          stub_mode('cidr')
          expect(mode).to eq('filter')
        end

        it 'falls back to filter for garbage' do
          stub_mode('!!!')
          expect(mode).to eq('filter')
        end

        it 'falls back to filter for a non-string value' do
          stub_mode(2)
          expect(mode).to eq('filter')
        end

        it 'does not raise' do
          stub_mode('dept')
          expect { mode }.not_to raise_error
        end

        it 'warns naming the rejected value and the mode actually in force' do
          stub_mode('dept')
          mode
          aggregate_failures do
            expect(OT).to have_received(:lw).with(/dept/)
            expect(OT).to have_received(:lw).with(/filter/)
          end
        end

        it 'names the valid values so the operator can fix it without the source' do
          stub_mode('dept')
          mode
          expect(OT).to have_received(:lw).with(/depth/)
        end

        it 'warns once across repeated calls' do
          # Seven Application subclasses each build a stack and reach this
          # reader; the operator should read one finding, not seven.
          stub_mode('dept')
          3.times { described_class.trusted_proxy_mode }
          expect(OT).to have_received(:lw).once
        end

        it 'still warns when the value is only unrecognized after downcasing' do
          stub_mode('Dept')
          aggregate_failures do
            expect(mode).to eq('filter')
            expect(OT).to have_received(:lw).with(/not a recognized mode/)
          end
        end
      end
    end
  end
end
