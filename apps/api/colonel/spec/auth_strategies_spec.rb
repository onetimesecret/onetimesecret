# apps/api/colonel/spec/auth_strategies_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/auth_strategies'
require 'onetime/middleware/strip_forwarded_host'
require 'onetime/session'

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
          'x-ots-proxy-debug-client-ip' => nil,
          'x-ots-proxy-debug-host' => nil,
          'x-ots-proxy-debug-received-x-forwarded-for' => nil,
          'x-ots-proxy-debug-received-x-forwarded-host' => nil,
          'x-ots-proxy-debug-received-x-real-ip' => nil,
          'x-ots-proxy-debug-received-x-client-ip' => nil,
          'x-ots-proxy-debug-received-forwarded' => nil,
          'x-ots-proxy-debug-received-apx-incoming-host' => nil,
        },
        rack: {
          remote_addr: '10.0.0.4',
          client_ip: '203.0.113.0',
          via_trusted_proxy: true,
          detected_host: 'tenant.example.test',
          stripped_forwarded_headers: [],
        },
        request_headers: {
          'host' => 'origin.example.test',
          'x-forwarded-for' => '203.0.113.9',
          'x-forwarded-host' => nil,
          'x-forwarded-proto' => nil,
          'x-real-ip' => nil,
          'x-client-ip' => nil,
          'forwarded' => nil,
          'apx-incoming-host' => 'tenant.example.test',
        },
      )
    end

    it 'reports the carriers StripForwardedHost deleted, by wire name' do
      # The middleware has already deleted HTTP_FORWARDED / HTTP_X_FORWARDED_HOST
      # by the time any app runs; only its record of the deletion is left.
      env['onetime.stripped_forwarded_headers'] = %w[HTTP_X_FORWARDED_HOST HTTP_FORWARDED].freeze

      metadata = strategy.send(:build_metadata, env)

      expect(metadata[:proxy_header_debug][:rack][:stripped_forwarded_headers]).to eq(%w[x-forwarded-host forwarded])
    end

    it 'reads the stripped-carrier record through the same env key the middleware and Session use' do
      # Three files name this seam with their own literal so none has to load
      # the others; a rename in one would leave every suite green while the
      # diagnostics silently went back to "permanently absent".
      expect([described_class::STRIPPED_FORWARDED_HEADERS, Onetime::Session::STRIPPED_FORWARDED_HEADERS])
        .to all(eq(Onetime::Middleware::StripForwardedHost::STRIPPED_HEADERS))
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

  # Destructive-action confirmation transport (#4326). This is the ONLY request
  # header ordinary colonel metadata carries: logic classes never see the Rack
  # env, so the X-OTS-Confirm value has to arrive through here.
  describe 'the confirmation header' do
    def confirm_token_for(raw)
      request_env = { 'PATH_INFO' => '/users/ur_target' }
      request_env['HTTP_X_OTS_CONFIRM'] = raw unless raw.nil?
      strategy.send(:build_metadata, request_env)[:confirm_token]
    end

    it 'surfaces the header on an ordinary colonel request' do
      expect(confirm_token_for('victim%40example.com')).to eq('victim@example.com')
    end

    it 'surfaces it on the diagnostic route too (merged before that branch)' do
      env['HTTP_X_OTS_CONFIRM'] = 'anything'
      metadata = strategy.send(:build_metadata, env)

      expect(metadata[:confirm_token]).to eq('anything')
      expect(metadata).to have_key(:proxy_header_debug)
    end

    it 'is nil when the header is absent or empty' do
      expect(confirm_token_for(nil)).to be_nil
      expect(confirm_token_for('')).to be_nil
    end

    # HTTP header values are ISO-8859-1 by RFC 7230, so a non-ASCII token (an
    # org display name) has to be percent-encoded by the client and decoded here.
    it 'percent-decodes a non-ASCII token back to UTF-8' do
      token = confirm_token_for('Acme%20Gmbh%20%C3%9Cberwachung')

      expect(token).to eq('Acme Gmbh Überwachung')
      expect(token.encoding).to eq(Encoding::UTF_8)
    end

    it 'leaves a plain ASCII token untouched, so curl works as typed' do
      expect(confirm_token_for('victim@example.com')).to eq('victim@example.com')
    end

    it 'rejects an over-long header whole rather than truncating it (a sliced token would 403 anyway)' do
      cap = described_class::MAX_CONFIRM_BYTES

      # Over the ceiling → no token. Truncating instead would sever a %XX escape
      # or a multibyte char and turn a valid token into a permanent 403.
      expect(confirm_token_for('a' * (cap + 1))).to be_nil
      # Exactly at the ceiling still decodes.
      expect(confirm_token_for('a' * cap)).to eq('a' * cap)
    end

    # #4326: the cap is on the ENCODED bytes, so a max-length multibyte token —
    # an org display_name is up to 100 chars, ~900 bytes once encodeURIComponent'd
    # — must survive. The old 512-byte slice severed it into a 403.
    it 'decodes a long percent-encoded multibyte token that exceeds the former cap' do
      name    = '中' * 100
      encoded = name.chars.map { |ch| ch.bytes.map { |b| format('%%%02X', b) }.join }.join

      expect(encoded.bytesize).to be > 512 # would have been truncated before
      expect(confirm_token_for(encoded)).to eq(name)
    end

    # #4326: FORM decoding accepts the widest range of correct encodings for a
    # token that routinely contains SPACES (org display_names): a form-encoded
    # space ('+') decodes to a space, so it confirms whether the client sent '%20'
    # or '+'. A literal '+' is sent '%2B' (encodeURIComponent and form encoders
    # both do), which round-trips to a literal '+'.
    it 'decodes a form-encoded space (+) to a space, and %2B to a literal +' do
      expect(confirm_token_for('Acme+Corp')).to eq('Acme Corp')
      expect(confirm_token_for('ops%2Badmin@example.com')).to eq('ops+admin@example.com')
    end

    it 'treats an undecodable header as no token rather than raising' do
      allow(Rack::Utils).to receive(:unescape).and_raise(ArgumentError, 'bad encoding')

      expect(confirm_token_for('anything')).to be_nil
    end
  end
end
