# spec/integration/full/impersonation_rack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/protection'

# apps/api is in the load path from spec_helper
require 'colonel/application'

# End-to-end coverage of colonel impersonation through the REAL rack stack:
# session middleware -> ImpersonationContext -> auth strategies -> handlers ->
# serializers, with real Customer models and a real encrypted session blob
# carried between requests by the cookie jar.
#
# The unit specs prove each piece in isolation. What only this level can prove
# is that the pieces AGREE: that the marker one request writes is the marker
# the next request's identity resolution reads, that the guard sits upstream of
# routing (so a blocked verb never reaches a handler), and that the bootstrap
# payload describes the same customer the API is actually serving. A design
# where the banner and the served identity are computed from two different
# reads of the session is exactly the bug this feature must not ship.
#
# Full mode, because that is the mode the admin console runs in
# (spec/integration/full — see the mode contract; full-sqlite runs
# rake spec:integration:full).
RSpec.describe 'Colonel impersonation through the rack stack', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    ENV['AUTHENTICATION_MODE'] = 'full'
    Onetime::Application::Registry.reset!
    Onetime.auth_config.reload!
    Onetime.boot! :test
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:run_id) { "imp_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  # The role gate for /api/colonel requires role='colonel' AND a verified
  # email (defense-in-depth in authorization_policies.rb) — and so does the
  # impersonation resolver's operator? check.
  let!(:colonel) do
    customer          = Onetime::Customer.create!(email: "#{run_id}_colonel@test.com")
    customer.role     = 'colonel'
    customer.verified = 'true'
    customer.save
    customer
  end

  let!(:target) do
    customer          = Onetime::Customer.create!(email: "#{run_id}_target@test.com")
    customer.verified = 'true'
    customer.save
    customer
  end

  # Seeded into env['rack.session']; Rack::Session#prepare_session MERGES this
  # into the real (cookie-backed, Redis-persisted) session on every request, so
  # it keeps the operator authenticated without pinning anything the app writes.
  let(:seed_session) do
    {
      'external_id' => colonel.extid,
      'role' => 'colonel',
      'authenticated' => true,
      'authenticated_at' => Familia.now.to_i,
    }
  end

  let(:read_only_message) do
    'This session is impersonating a customer and is read-only. ' \
      'Stop impersonating to make changes.'
  end

  before do
    # Mint :csrf into the seed before the first request so the session-gated
    # CSRF middleware accepts the masked token on POSTs.
    Rack::Protection::AuthenticityToken.token(seed_session)
    env 'rack.session', seed_session
  end

  after do
    Onetime::SessionImpersonation.clear_context
    target&.destroy! rescue nil
    colonel&.destroy! rescue nil
  end

  def csrf_header
    header 'X-CSRF-Token', Rack::Protection::AuthenticityToken.token(seed_session)
  end

  def post_json(path, payload = {})
    csrf_header
    post path, payload.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  def body_json
    JSON.parse(last_response.body)
  end

  def bootstrap
    get '/bootstrap/me'
    expect(last_response.status).to eq(200)
    JSON.parse(last_response.body)
  end

  def start_impersonation(reason: 'ticket #4242')
    post_json("/api/colonel/users/#{target.extid}/impersonate", reason: reason)
  end

  # Global capped set shared by the whole forest datastore, so filter by this
  # run's target rather than asserting on position.
  def audit_events_for_target
    Onetime::ColonelAuditEvent.recent(200).select { |event| event['target'] == target.extid }
  end

  def detail_for(event)
    detail = event['detail']
    detail.is_a?(Hash) ? detail : {}
  end

  describe 'the full operator round trip' do
    it 'starts, serves the target read-only, blocks writes, and restores the colonel' do
      # --- 1. START ----------------------------------------------------
      start_impersonation

      expect(last_response.status).to eq(200), "start failed: #{last_response.body}"
      record = body_json['record']
      expect(record['impersonation_id']).to match(/\Aimp_[0-9a-f]{16}\z/)
      expect(record['target_extid']).to eq(target.extid)
      expect(record['target_email']).to eq(target.email)
      expect(record['redirect']).to eq('/')
      impersonation_id = record['impersonation_id']

      # --- 2. BOOTSTRAP describes the TARGET, and says so --------------
      payload = bootstrap
      expect(payload['authenticated']).to be true
      expect(payload['custid']).to eq(target.custid)
      expect(payload['impersonation']).to eq(
        'impersonation_id' => impersonation_id,
        'impersonator_extid' => colonel.extid,
        'target_extid' => target.extid,
        'target_email' => target.email,
        'started_at' => payload['impersonation']['started_at'],
        'expires_at' => payload['impersonation']['expires_at'],
      )
      expect(payload['impersonation']['expires_at'] - payload['impersonation']['started_at'])
        .to eq(Onetime::SessionImpersonation::TTL)

      # --- 3. customer-surface READ is allowed -------------------------
      get '/api/account/'
      expect(last_response.status).to eq(200), "customer read failed: #{last_response.body}"

      # --- 4. any WRITE is refused, upstream of the handler ------------
      post_json('/api/v3/secret/conceal', secret: 'nope')
      expect(last_response.status).to eq(403)
      expect(body_json).to eq(
        'error' => read_only_message,
        'error_code' => 'impersonation_read_only',
      )

      # --- 5. a GET that is really a burn is refused too ---------------
      # V2::Logic::Secrets::ShowSecret gates burn-after-reading on the
      # `continue` param, not on the HTTP method.
      get "/api/v2/secret/#{SecureRandom.hex(8)}?continue=true"
      expect(last_response.status).to eq(403)
      expect(body_json['error_code']).to eq('impersonation_read_only')

      # --- 6. no admin powers while presenting as a customer -----------
      get '/api/colonel/info'
      expect(last_response.status).to eq(403)
      expect(body_json['error_code']).to eq('impersonation_read_only')

      # --- 7. STOP ------------------------------------------------------
      post_json('/api/account/impersonation/stop')

      expect(last_response.status).to eq(200), "stop failed: #{last_response.body}"
      stop_record = body_json['record']
      expect(stop_record['stopped']).to be true
      expect(stop_record['target_extid']).to eq(target.extid)
      expect(stop_record['redirect']).to eq("/colonel/customers/#{target.extid}")

      # --- 8. the colonel is back --------------------------------------
      restored = bootstrap
      expect(restored['impersonation']).to be_nil
      expect(restored['custid']).to eq(colonel.custid)

      get '/api/colonel/info'
      expect(last_response.status).to eq(200), "colonel not restored: #{last_response.body}"

      # --- 9. both ends are in the trail, correlated -------------------
      events = audit_events_for_target
      start_event = events.find { |e| e['verb'] == 'customer.impersonate.start' }
      stop_event  = events.find { |e| e['verb'] == 'customer.impersonate.stop' }

      expect(start_event).not_to be_nil, "no start event in #{events.map { |e| e['verb'] }}"
      expect(stop_event).not_to be_nil, "no stop event in #{events.map { |e| e['verb'] }}"
      expect(start_event['actor']).to eq(colonel.extid)
      expect(stop_event['actor']).to eq(colonel.extid)
      expect(detail_for(start_event)['impersonation_id']).to eq(impersonation_id)
      expect(detail_for(stop_event)['impersonation_id']).to eq(impersonation_id)
      expect(detail_for(stop_event)['ended_by']).to eq('operator')
      expect(detail_for(start_event)['reason']).to eq('ticket #4242')
    end
  end

  describe 'refusals at the start endpoint' do
    it 'requires a reason' do
      post_json("/api/colonel/users/#{target.extid}/impersonate", reason: '  ')

      expect(last_response.status).to eq(422), last_response.body
    end

    it 'refuses a colonel target' do
      target.role = 'colonel'
      target.save

      start_impersonation

      expect(last_response.status).to eq(422), last_response.body
    end

    it 'refuses a suspended target' do
      target.suspended = 'true'
      target.save

      start_impersonation

      expect(last_response.status).to eq(422), last_response.body
    end

    it '404s an unknown user' do
      post_json('/api/colonel/users/ur_does_not_exist/impersonate', reason: 'x')

      expect(last_response.status).to eq(404), last_response.body
    end
  end

  describe 'the stop endpoint is invisible without a marker' do
    it '404s an ordinary colonel session rather than admitting it exists' do
      post_json('/api/account/impersonation/stop')

      expect(last_response.status).to eq(404), last_response.body
    end
  end

  describe 'expiry' do
    # No time travel: the marker carries its own deadline, so seeding one that
    # is already past exercises the same branch deterministically.
    let(:expired_marker) do
      started = Familia.now.to_i - Onetime::SessionImpersonation::TTL - 60
      {
        'id' => "imp_#{SecureRandom.hex(8)}",
        'target_extid' => target.extid,
        'target_email' => target.email,
        'reason' => 'ticket #expired',
        'started_at' => started,
        'expires_at' => started + Onetime::SessionImpersonation::TTL,
      }
    end

    before do
      env 'rack.session',
        seed_session.merge(Onetime::SessionImpersonation::SESSION_KEY => expired_marker)
    end

    it 'ends the impersonation, audits it as expired, and stops guarding' do
      # A LIVE marker would 403 this; an expired one must not.
      post_json('/api/v3/secret/conceal', secret: 'nope')

      expect(last_response.status).not_to eq(403)
      expect(last_response.body).not_to include('impersonation_read_only')

      stop_event = audit_events_for_target.find { |e| e['verb'] == 'customer.impersonate.stop' }
      expect(stop_event).not_to be_nil
      expect(detail_for(stop_event)['ended_by']).to eq('expired')
      expect(detail_for(stop_event)['impersonation_id']).to eq(expired_marker['id'])
      expect(stop_event['actor']).to eq(colonel.extid)
    end

    it 'serves the colonel, not the target, on an expired marker' do
      payload = bootstrap

      expect(payload['impersonation']).to be_nil
      expect(payload['custid']).to eq(colonel.custid)
    end
  end
end
