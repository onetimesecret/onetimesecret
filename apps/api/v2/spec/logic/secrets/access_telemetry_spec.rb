# apps/api/v2/spec/logic/secrets/access_telemetry_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'onetime/security/request_context'

# Logic-layer coverage for the network-context half of AccessTelemetry
# (#3640 capture, #3989 country resolution).
#
# The load-bearing property here is the COMPLIANCE GATE: country capture on
# the org-tier Secret Activity trail is DEFAULT-OFF (opt-in) pending counsel
# review of org-tier geo exposure (ADR-021 Decision 4; ADR-022 does not yet
# cover net_country). The gate lives entirely at this layer -- RequestContext
# happily stores any well-formed country it is handed -- so if
# #geo_country_enabled? ever regressed to default-on, nothing downstream
# would catch it. These examples pin:
#
#   * flag OFF (the shipped default) => country: nil reaches capture and
#     net_country is absent from the attrs, EVEN when the auth strategy
#     resolved a real country;
#   * flag ON => a valid country is captured, and Otto's '**' unknown
#     sentinel still never becomes a stored value;
#   * the flag's `.to_s == 'true'` coercion contract, which must stay in
#     lockstep with the frontend exposure gate in ConfigSerializer
#     (build_feature_flags) or the UI shows a Country column the backend
#     never populates;
#   * the best-effort rescue: capture failure logs and yields {}, never
#     raising into the read path.
RSpec.describe V2::Logic::Secrets::AccessTelemetry, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  # The network-context half of the module depends on nothing but
  # #strategy_result, so a minimal host exercises it without dragging in a
  # full logic class (params processing, secret loading, actor attribution).
  let(:telemetry_host) do
    Class.new do
      include V2::Logic::Secrets::AccessTelemetry

      attr_reader :strategy_result

      def initialize(strategy_result)
        @strategy_result = strategy_result
      end
    end
  end

  # What Otto's auth strategy resolves into StrategyResult metadata: an
  # already edge-masked IP/UA plus the geo-resolved country (#3989).
  let(:metadata) do
    {
      ip: '203.0.113.42',
      user_agent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/119.0.0.0 Safari/537.36',
      country: 'US',
    }
  end

  def build_host(strategy_metadata = metadata)
    telemetry_host.new(double('StrategyResult', metadata: strategy_metadata))
  end

  # Both methods under test are private (module internals reached only via
  # #record_access_telemetry); call them as the module does.
  def network_context(strategy_metadata = metadata)
    build_host(strategy_metadata).send(:request_network_context)
  end

  def geo_enabled?
    build_host.send(:geo_country_enabled?)
  end

  # Same OT.conf stubbing idiom as the org trail's collection-toggle specs:
  # merge the flag onto the real booted config so only this key varies.
  def stub_secret_activity_conf(secret_activity)
    base     = OT.conf
    features = (base['features'] || {}).merge('secret_activity' => secret_activity)
    allow(OT).to receive(:conf).and_return(base.merge('features' => features))
  end

  def stub_geo_flag(value)
    stub_secret_activity_conf('geo_country_enabled' => value)
  end

  describe '#geo_country_enabled? (default-OFF opt-in contract)' do
    # Parity with ConfigSerializer#build_feature_flags, which gates the UI
    # Country column on the same `.to_s == 'true'` test. Divergence in either
    # direction is a visible bug: a column with no data, or captured geo the
    # operator believes is off.
    it "enables only on boolean true or the string 'true' (ERB / hand-edited YAML parity)" do
      aggregate_failures do
        stub_geo_flag(true)
        expect(geo_enabled?).to be true

        stub_geo_flag('true')
        expect(geo_enabled?).to be true
      end
    end

    it "stays off for false, 'false', nil, and an absent key (older config file)" do
      aggregate_failures do
        stub_geo_flag(false)
        expect(geo_enabled?).to be false

        stub_geo_flag('false')
        expect(geo_enabled?).to be false

        stub_geo_flag(nil)
        expect(geo_enabled?).to be false

        # Key absent from an existing secret_activity block...
        stub_secret_activity_conf('collect' => true)
        expect(geo_enabled?).to be false

        # ...and the whole block absent (pre-#3989 config file).
        stub_secret_activity_conf(nil)
        expect(geo_enabled?).to be false
      end
    end
  end

  describe '#request_network_context' do
    # THE ADR-021 DECISION 4 COMPLIANCE ASSERTION. With the shipped default
    # (flag off), a country the auth strategy DID resolve must never reach
    # the trail: capture is called with country: nil and the resulting attrs
    # carry no net_country key at all. The gate is narrow by design -- the
    # IP/UA attributes are unaffected -- so this example pins both halves.
    it 'does not capture country when the flag is off, even though the strategy resolved one ' \
       '(ADR-021 Decision 4: org-tier geo stays gated pending counsel review)' do
      stub_geo_flag(false)

      expect(Onetime::Security::RequestContext)
        .to receive(:capture).with(hash_including(country: nil)).and_call_original

      attrs = network_context

      aggregate_failures do
        expect(attrs).not_to have_key('net_country')
        expect(attrs.to_json).not_to include('US')
        # The gate covers country ONLY: the rest of the context still lands.
        expect(attrs['net_ip_partial']).to eq('203.0.113.0')
        expect(attrs['net_ua_partial']).to include('Chrome')
      end
    end

    it 'captures the resolved country as net_country when the flag is on' do
      stub_geo_flag(true)

      attrs = network_context

      aggregate_failures do
        expect(attrs['net_country']).to eq('US')
        expect(attrs['net_ip_partial']).to eq('203.0.113.0')
      end
    end

    # Otto's GeoResolver returns '**' when it cannot resolve a country. Even
    # with capture enabled that sentinel is never stored -- an event with no
    # resolvable country carries no net_country key rather than a literal
    # '**' an audit consumer would have to special-case.
    it "omits net_country for Otto's '**' unknown sentinel while the flag is on" do
      stub_geo_flag(true)

      attrs = network_context(metadata.merge(country: '**'))

      aggregate_failures do
        expect(attrs).not_to have_key('net_country')
        expect(attrs.to_json).not_to include('**')
        expect(attrs['net_ip_partial']).to eq('203.0.113.0')
      end
    end

    # Best-effort by design (#3640): telemetry must never break or delay the
    # read path, so a capture failure is logged and swallowed, and the event
    # records with no network attributes rather than propagating.
    it 'logs and returns {} when capture raises, never breaking the read path' do
      stub_geo_flag(true)

      exploding = double('StrategyResult')
      allow(exploding).to receive(:metadata).and_raise(RuntimeError, 'boom')
      host = telemetry_host.new(exploding)

      expect(OT).to receive(:le).with(/network-context capture failed/)

      result = nil
      expect { result = host.send(:request_network_context) }.not_to raise_error
      expect(result).to eq({})
    end
  end
end
