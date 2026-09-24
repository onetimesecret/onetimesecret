# spec/unit/onetime/session_cookie_security_spec.rb
#
# frozen_string_literal: true
#
# Audit 2026-08-02, findings L-1 / L-3 / L-4.
#
# L-1: the Secure cookie flag must (a) default to true in production even when
#      the SSL env var / site.ssl is unset (boot.rb#session_config +
#      #ssl_enabled?), and (b) be applied per-request whenever the request
#      itself is HTTPS — Rack::Request#ssl? honors X-Forwarded-Proto, and the
#      AssumeHttps middleware (#3837/#3843) covers tunnels that don't forward
#      it — via the upgrade-only Onetime::Session#set_cookie override.
#
# L-3: no log line carries the session id; the full id is the bearer
#      credential. Log lines carry session_handle, the keyed digest of the id
#      (#4461, Onetime::SessionMetadata.handle_for), which the colonel session
#      view shows and which cannot be turned back into the id.
# L-4: the "Session saved successfully" entry must not disclose
#      account_id/external_id/MFA state/key names.

require 'spec_helper'
require 'onetime/session'

RSpec.describe Onetime::Session do
  let(:secret)   { 'a' * 64 }
  let(:app)      { ->(_env) { [200, {}, []] } }
  let(:dbclient) { double('dbclient') }

  # Session middleware with an injected dbclient so no spec here ever needs a
  # live Valkey; the codec and the log/cookie seams under test are pure Ruby.
  let(:middleware) { described_class.new(app, secret: secret, dbclient: dbclient, expire_after: 3600) }

  def request_for(url, opts = {})
    Rack::Request.new(Rack::MockRequest.env_for(url, opts))
  end

  # Drives the private set_cookie seam and returns the cookie hash the parent
  # would hand to Rack (nil when the parent skipped the write).
  def committed_cookie(request, cookie)
    captured = nil
    response = double('response')
    allow(response).to receive(:set_cookie) { |_key, value| captured = value }
    middleware.send(:set_cookie, request, response, cookie)
    captured
  end

  describe '#set_cookie Secure upgrade (L-1)' do
    it 'adds Secure when the request is HTTPS even though secure was not configured' do
      cookie = committed_cookie(request_for('https://example.com/'), { value: 'sid' })
      expect(cookie[:secure]).to be true
    end

    it 'adds Secure behind a TLS-terminating proxy via X-Forwarded-Proto' do
      request = request_for('http://example.com/', 'HTTP_X_FORWARDED_PROTO' => 'https')
      expect(request.ssl?).to be true # sanity: Rack honors the forwarded scheme

      cookie = committed_cookie(request, { value: 'sid' })
      expect(cookie[:secure]).to be true
    end

    it 'leaves a plain-HTTP request without the Secure flag (upgrade-only)' do
      cookie = committed_cookie(request_for('http://example.com/'), { value: 'sid' })
      expect(cookie[:secure]).to be_falsey
    end

    it 'never downgrades a configured secure: true' do
      cookie = committed_cookie(request_for('https://example.com/'), { value: 'sid', secure: true })
      expect(cookie[:secure]).to be true
    end
  end

  describe '#log_handle (L-3)' do
    let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }

    it 'is the keyed session handle, sharing no prefix with the id', :aggregate_failures do
      handle = middleware.send(:log_handle, sid)
      expect(handle).to eq(Onetime::SessionMetadata.handle_for(sid))
      expect(handle).not_to include(sid[0, 8])
    end

    it 'unwraps Rack SessionId objects' do
      session_id = Rack::Session::SessionId.new(sid)
      expect(middleware.send(:log_handle, session_id)).to eq(middleware.send(:log_handle, sid))
    end

    it 'is nil, never a fabricated value, when there is no id' do
      expect(middleware.send(:log_handle, nil)).to be_nil
    end
  end

  describe 'log redaction' do
    let(:log_entries) { [] }
    let(:spy_logger) do
      logger = double('session_logger')
      %i[trace debug info warn error].each do |level|
        allow(logger).to receive(level) { |msg, fields = {}| log_entries << [level, msg, fields] }
      end
      logger
    end

    before do
      allow(middleware).to receive(:session_logger).and_return(spy_logger)
    end

    it 'never logs the session id on the invalid-sid read path', :aggregate_failures do
      long_invalid_sid = 'Z' * 64 # invalid format, so no Redis lookup happens
      middleware.send(:find_session, request_for('/'), long_invalid_sid)

      handles = log_entries.map { |_, _, fields| fields[:session_handle] }.compact
      expect(handles).not_to be_empty
      expect(handles).to include(middleware.send(:log_handle, long_invalid_sid))
      log_entries.each do |_, _, fields|
        expect(fields).not_to have_key(:session_id)
        expect(fields.values.map(&:to_s).join(' ')).not_to include(long_invalid_sid)
      end
    end

    describe "'Session saved successfully' entry (L-4)" do
      let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }
      let(:session_data) do
        {
          'account_id' => 12_345,
          'external_id' => 'cust_deadbeef',
          'authenticated' => true,
          'authenticated_at' => 1_754_000_000,
          'awaiting_mfa' => false,
          'two_factor_auth_setup' => true,
        }
      end

      let(:saved_entry) do
        # Neutralize the Redis-touching collaborators: the sidecar commit and
        # the Familia StringKey. Everything else in write_session is pure.
        stringkey = double('stringkey', set: true, update_expiration: true, ttl: 3600)
        allow(middleware).to receive(:get_stringkey).and_return(stringkey)
        allow(Onetime::SessionSidecar).to receive(:commit).and_return(session_data)
        allow(Onetime::SessionEnded).to receive(:ended?).and_return(false)
        allow(Onetime::Operations::Sessions::TrackMetadata)
          .to receive(:new).and_return(double(call: true))

        middleware.send(:write_session, request_for('/'), sid, session_data, {})
        log_entries.find { |_, msg, _| msg == 'Session saved successfully' }
      end

      it 'carries the session handle, not the session id', :aggregate_failures do
        _, _, fields = saved_entry
        expect(fields[:session_handle]).to eq(middleware.send(:log_handle, sid))
        expect(fields).not_to have_key(:session_id)
      end

      it 'does not disclose account identity or MFA/auth-state details' do
        _, _, fields = saved_entry
        expect(fields).not_to include(
          :account_id, :external_id, :authenticated_at,
          :awaiting_mfa, :two_factor_auth_setup, :session_keys
        )
      end

      it 'keeps the operational fields debugging needs' do
        _, _, fields = saved_entry
        expect(fields[:authenticated]).to be true
        expect(fields[:key_count]).to eq(session_data.size)
        expect(fields[:ttl]).to eq(3600)
        expect(fields).to include(:data_size, :expires_at)
      end

      it 'never emits the raw sid or the redis key in any write-path entry' do
        saved_entry # drive the write
        log_entries.each do |_, _, fields|
          expect(fields.values.map(&:to_s).join(' ')).not_to include(sid)
          expect(fields).not_to have_key(:redis_key)
        end
      end
    end

    describe 'delete path' do
      let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }

      # Neutralize the Familia StringKey, the ended-marker write and the
      # metadata record; the sidecar probe and purge are stubbed per example to
      # drive the warn and error branches, which run outside the blob-exists
      # branch (v0.26.12) and must still keep the sid out of the log.
      def destroy_session
        allow(middleware).to receive(:get_stringkey).and_return(double('stringkey', del: 1))
        allow(Onetime::SessionEnded).to receive(:mark).and_return(true)
        allow(Onetime::SessionMetadata).to receive(:load).and_return(nil)
        middleware.send(:delete_session, request_for('/'), sid, {})
      end

      def entry_for(message)
        log_entries.find { |_, msg, _| msg == message }
      end

      it 'logs the session handle on the in-flight sidecar warning' do
        allow(Onetime::SessionSidecar).to receive(:inflight_fields).and_return(['awaiting_mfa'])
        allow(Onetime::SessionSidecar).to receive(:purge)
        destroy_session

        _, _, fields = entry_for('Session destroyed with in-flight sidecar state')
        expect(fields[:session_handle]).to eq(middleware.send(:log_handle, sid))
      end

      it 'logs the session handle on the sidecar purge failure' do
        allow(Onetime::SessionSidecar).to receive(:inflight_fields).and_return([])
        allow(Onetime::SessionSidecar).to receive(:purge).and_raise(StandardError, 'boom')
        destroy_session

        _, _, fields = entry_for('Sidecar purge failed (orphans are TTL-bounded)')
        expect(fields[:session_handle]).to eq(middleware.send(:log_handle, sid))
      end

      { 'purge succeeds' => false, 'purge raises' => true }.each do |label, purge_raises|
        it "never emits the raw sid or the redis key in any delete-path entry (#{label})" do
          allow(Onetime::SessionSidecar).to receive(:inflight_fields).and_return(['awaiting_mfa'])
          purge = allow(Onetime::SessionSidecar).to receive(:purge)
          purge.and_raise(StandardError, 'boom') if purge_raises
          destroy_session

          expect(log_entries).not_to be_empty
          log_entries.each do |_, _, fields|
            expect(fields.values.map(&:to_s).join(' ')).not_to include(sid)
            expect(fields).not_to have_key(:redis_key)
          end
        end
      end
    end
  end
end

RSpec.describe 'Onetime.session_config secure default (L-1)' do
  def config_with(site)
    allow(Onetime).to receive(:conf).and_return({ 'site' => site })
  end

  it 'defaults secure to true in production even when SSL/site.ssl is unset' do
    config_with({})
    allow(Onetime).to receive(:env).and_return('production')

    expect(Onetime.session_config['secure']).to be true
  end

  it 'defaults secure to true whenever site.ssl is set, in any env' do
    config_with('ssl' => true)
    allow(Onetime).to receive(:env).and_return('development')

    expect(Onetime.session_config['secure']).to be true
  end

  it 'leaves secure false in non-production without site.ssl' do
    config_with({})
    allow(Onetime).to receive(:env).and_return('development')

    expect(Onetime.session_config['secure']).to be false
  end

  it 'honors an explicit site.session.secure over the fallback' do
    config_with('session' => { 'secure' => false })
    allow(Onetime).to receive(:env).and_return('production')

    expect(Onetime.session_config['secure']).to be false
  end
end
