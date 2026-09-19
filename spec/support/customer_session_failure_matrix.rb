# frozen_string_literal: true

require 'json'
require 'nokogiri'

# The cross-surface customer-session failure matrix (#4452), in executable
# form. STATES is the machine-readable matrix: one row per session state, and
# per row what every surface must answer. The prose twin, with the divergences
# called out, is docs/authentication/customer-session-failure-matrix.md; change
# them together.
#
# Row keys:
#   verdict      CustomerSessionEvaluator status memoized for the request
#   markers      the bracket marker the session strategy fails with, per surface
#   protected    :refused (302 HTML / 401 API) or :authenticated
#   public       what hydration and GET /bootstrap/me expose
#   auth_status  the wire `auth_status` on both public surfaces (#4462)
#   code, scope  the wire `code` / `code_scope` on the protected API 401
#                (#4462); nil when the request is not refused
#   ordered      whether both public surfaces carry the ADR-046 ordering pair
#                (#4457): only a payload that reports a session does
#   activity     what each surface does to the active-session row
module CustomerSessionFailureMatrix
  SURFACES = {
    protected_html: { path: '/dashboard', accept: 'text/html' },
    hydrated_html: { path: '/', accept: 'text/html', bootstrap: :html },
    bootstrap: { path: '/bootstrap/me', accept: 'application/json', bootstrap: :json },
    protected_api: { path: '/api/account/', accept: 'application/json' },
  }.freeze

  NO_ACTIVITY = SURFACES.keys.to_h { |surface| [surface, :unchanged] }.freeze
  NO_ACTIVE_SESSION = SURFACES.keys.to_h { |surface| [surface, :not_applicable] }.freeze
  EXPIRED_ACTIVITY = SURFACES.keys.to_h { |surface| [surface, :deleted] }.freeze
  FULL_MODE_ACTIVE_SESSION_STATES = %i[
    revoked
    inactive
    absolute_expired
    authentication_database_unavailable
  ].freeze
  SIMPLE_MODE_STATES = %i[
    missing_anonymous
    legacy_unstamped
    mfa_pending
    suspended
    credential_stale
    tenant_surface_mismatch
  ].freeze
  MFA_PROTECTED_ACCOUNT_FIELDS = {
    'cust' => nil,
    'custid' => nil,
    'customer_since' => nil,
    'has_password' => false,
    'entitlement_preview_planid' => nil,
    'entitlement_preview_plan_name' => nil,
    'impersonation' => nil,
  }.freeze

  class SqlCapture
    attr_reader :messages

    def initialize
      @messages = []
    end

    def info(message)
      @messages << message
    end

    def warn(message); end
    def error(message); end
  end

  def self.request_markers(marker)
    SURFACES.keys.to_h do |surface|
      [surface, %i[protected_html protected_api].include?(surface) && marker ? [marker] : []]
    end.freeze
  end

  STATES = {
    missing_anonymous: {
      markers: request_markers('SESSION_NOT_AUTHENTICATED'),
      verdict: :anonymous,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'not_authenticated',
      scope: 'customer_session',
      ordered: false,
      activity: NO_ACTIVE_SESSION,
    },
    revoked: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'active_session_revoked',
      scope: 'customer_session',
      ordered: false,
      activity: NO_ACTIVE_SESSION,
    },
    inactive: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'active_session_revoked',
      scope: 'customer_session',
      ordered: false,
      activity: EXPIRED_ACTIVITY,
    },
    absolute_expired: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'active_session_revoked',
      scope: 'customer_session',
      ordered: false,
      activity: EXPIRED_ACTIVITY,
    },
    legacy_unstamped: {
      markers: request_markers(nil),
      verdict: :authenticated,
      protected: :authenticated,
      public: :identity_exposed,
      auth_status: 'authenticated',
      code: nil,
      scope: nil,
      ordered: true,
      activity: NO_ACTIVITY,
    },
    mfa_pending: {
      markers: request_markers('SESSION_AWAITING_MFA'),
      verdict: :mfa_pending,
      protected: :refused,
      public: :mfa_pending,
      auth_status: 'mfa_pending',
      code: 'awaiting_mfa',
      scope: 'customer_session',
      ordered: true,
      activity: NO_ACTIVITY,
    },
    suspended: {
      markers: request_markers('ACCOUNT_SUSPENDED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'account_suspended',
      scope: 'customer_session',
      ordered: false,
      activity: NO_ACTIVITY,
    },
    credential_stale: {
      markers: request_markers('SESSION_STALE_CREDENTIALS'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'stale_credentials',
      scope: 'customer_session',
      ordered: false,
      activity: NO_ACTIVITY,
    },
    tenant_surface_mismatch: {
      markers: request_markers('SESSION_SURFACE_MISMATCH'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      auth_status: 'anonymous',
      code: 'surface_mismatch',
      scope: 'customer_session',
      ordered: false,
      activity: NO_ACTIVITY,
    },
    authentication_database_unavailable: {
      markers: request_markers('SESSION_UNVERIFIED'),
      verdict: :unavailable,
      protected: :refused,
      public: :anonymous,
      auth_status: 'unavailable',
      code: 'active_session_unavailable',
      scope: 'verification_unavailable',
      ordered: false,
      activity: NO_ACTIVITY,
    },
    customer_storage_unavailable: {
      markers: request_markers('SESSION_UNVERIFIED'),
      verdict: :unavailable,
      protected: :refused,
      public: :anonymous,
      auth_status: 'unavailable',
      code: 'customer_unavailable',
      scope: 'verification_unavailable',
      ordered: false,
      activity: NO_ACTIVITY,
    },
  }.freeze

  def current_session_id
    rack_mock_session.cookie_jar['onetime.session']
  end

  def session_store
    Onetime::Operations::Sessions::Store
  end

  def session_codec
    Onetime::SessionCodec.from_config
  end

  def session_blob
    key = session_store.find_key(Familia.dbclient, current_session_id)
    session_store.load_data(Familia.dbclient, key, codec: session_codec)
  end

  def rewrite_session_blob
    db   = Familia.dbclient
    key  = session_store.find_key(db, current_session_id)
    data = session_store.load_data(db, key, codec: session_codec)
    yield data
    db.set(key, session_codec.encode(data), keepttl: true)
    data
  end

  def parse_bootstrap(response, format)
    case format
    when :json
      JSON.parse(response.body)
    when :html
      node = Nokogiri::HTML(response.body).css('script[type="application/json"]').first
      raise 'hydrated HTML did not include bootstrap JSON' unless node

      JSON.parse(node.content)
    end
  end

  def request_surface(surface, request_id:)
    config  = SURFACES.fetch(surface)
    markers = []
    allow_any_instance_of(Onetime::Application::AuthStrategies::SessionAuthStrategy)
      .to receive(:authenticate).and_wrap_original do |original, *args|
        result = original.call(*args)
        if result.is_a?(Otto::Security::Authentication::AuthFailure)
          markers << result.failure_reason[/\A\[(?<marker>[^\]]+)\]/, :marker]
        end
        result
      end

    get config.fetch(:path), {}, {
      'HTTP_ACCEPT' => config.fetch(:accept),
      'HTTP_X_REQUEST_ID' => request_id,
    }

    payload = parse_bootstrap(last_response, config[:bootstrap]) if config[:bootstrap] && last_response.status == 200
    body    = last_response.body

    {
      status: last_response.status,
      payload: payload,
      verdict: last_request.env[Onetime::CustomerSessionEvaluator::ENV_KEY]&.status,
      authenticated: payload&.fetch('authenticated', nil),
      awaiting_mfa: payload&.fetch('awaiting_mfa', nil),
      auth_status: payload&.fetch('auth_status', nil),
      snapshot_epoch: payload&.fetch('snapshot_epoch', nil),
      snapshot_version: payload&.fetch('snapshot_version', nil),
      snapshot_keys: payload ? payload.keys.grep(/\Asnapshot_/).sort : [],
      session_id_exposed: body.include?(current_session_id.to_s) && !current_session_id.to_s.empty?,
      customer_exposed: payload ? !payload['cust'].nil? : body.include?(@matrix_customer.extid),
      identity_exposed: body.include?(@matrix_customer.email) || body.include?(@matrix_customer.extid),
      refusal_markers: markers.compact.uniq,
      refusal_code: refusal_code(body),
      refusal_body: refusal_body(body),
      cache_control: last_response.headers['cache-control'],
      request_id: response_request_id(last_response),
    }
  end

  def refusal_code(body)
    parsed = JSON.parse(body)
    parsed['code'] || parsed['error_type'] || parsed['error']
  rescue JSON::ParserError
    body[/\[(?<marker>[A-Z0-9_]+)\]/, :marker]
  end

  # The parsed JSON refusal, for asserting that the pre-#4462 fields are
  # unchanged. nil for a non-JSON body (the protected-HTML redirect).
  def refusal_body(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) && parsed.key?('error') ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def response_request_id(response)
    parsed = JSON.parse(response.body)
    parsed['request_id'] || response.headers['x-request-id'] || response.headers['X-Request-ID']
  rescue JSON::ParserError
    response.headers['x-request-id'] || response.headers['X-Request-ID']
  end

  # Attach the SQL capture to every Sequel::Database that talks to the
  # account_active_session_keys table on this request path — both the
  # test_db (which the row-count assertions read through) and the
  # Auth::Database.connection (which the ActiveSessionGate's expiring DELETE
  # is issued against). The two are the SAME underlying PostgreSQL database
  # but distinct Sequel::Database instances whenever both FullModeSuiteDatabase
  # AND PostgresModeSuiteDatabase have set up in one process (each installs
  # its own Auth::Database.connection stub, and the last writer wins). Logging
  # only through test_db.loggers then misses the gate's DELETE/UPDATE and the
  # `deletes`/`updates` assertions fail vacuously.
  #
  # Auth::Database.connection may be stubbed to raise in outage-simulation
  # states (:authentication_database_unavailable); rescue so the capture setup
  # does not itself trigger the very error the state is meant to exercise.
  def capture_activity_writes
    logger = SqlCapture.new
    databases = [test_db]
    begin
      other = ::Auth::Database.connection
      databases << other if other && !databases.any? { |db| db.equal?(other) }
    rescue StandardError
      # Outage-simulation state: leave the capture attached to test_db only.
    end
    databases.each { |db| db.loggers << logger }
    result = yield
    writes = logger.messages.grep(/\b(?:INSERT|UPDATE|DELETE)\b.*\baccount_active_session_keys\b/i)
    [result, writes]
  ensure
    databases&.each { |db| db.loggers.delete(logger) if logger }
  end

  def active_session_rows
    return test_db[:account_active_session_keys].where(account_id: -1) unless @matrix_account

    test_db[:account_active_session_keys].where(account_id: @matrix_account[:id])
  end

  def activity_snapshot
    row = active_session_rows.first
    row && { created_at: row[:created_at], last_use: row[:last_use] }
  end

  def activity_count
    active_session_rows.count
  end

  def establish_matrix_session!
    clear_cookies
    @matrix_email   = "session-matrix-#{SecureRandom.hex(10)}@example.com"
    @matrix_account = create_verified_account(db: test_db, email: @matrix_email, password: matrix_password)
    post_json '/auth/login', { login: @matrix_email, password: matrix_password }
    raise "matrix login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200

    blob             = session_blob
    @matrix_account  = test_db[:accounts].where(id: @matrix_account[:id]).first
    @matrix_customer = Onetime::Customer.find_by_extid(blob.fetch('external_id'))
    raise 'matrix login did not resolve a Customer' unless @matrix_customer

    stale = Time.now - (Onetime::ActiveSessionGate::TOUCH_INTERVAL + 60)
    active_session_rows.update(last_use: stale)
  end

  def establish_simple_matrix_session!
    clear_cookies
    @matrix_email = "simple-session-matrix-#{SecureRandom.hex(10)}@example.com"
    @matrix_customer = Onetime::Customer.new(email: @matrix_email)
    @matrix_customer.update_passphrase(matrix_password)
    @matrix_customer.verified = 'true'
    @matrix_customer.save

    post_json '/auth/login', { login: @matrix_email, password: matrix_password }
    raise "simple matrix login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200

    blob = session_blob
    raise 'simple matrix login did not authenticate the Customer' unless blob['external_id'] == @matrix_customer.extid
    raise 'simple matrix login unexpectedly stamped an active-session join key' if blob.key?('active_session_id_hmac')
  end

  def apply_matrix_state!(state)
    case state
    when :missing_anonymous
      clear_cookies
      @matrix_account = nil
      @matrix_customer ||= anonymous_probe_customer
    when :revoked
      active_session_rows.delete
    when :inactive
      active_session_rows.update(last_use: Time.now - (Onetime::ActiveSessionGate::INACTIVITY_DEADLINE + 60))
    when :absolute_expired
      active_session_rows.update(created_at: Time.now - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE + 60))
    when :legacy_unstamped
      rewrite_session_blob { |blob| blob.delete('active_session_id_hmac') }
    when :mfa_pending
      rewrite_session_blob do |blob|
        blob.delete('authenticated')
        blob['awaiting_mfa'] = true
      end
    when :suspended
      @matrix_customer.suspended = 'true'
      @matrix_customer.save
    when :credential_stale
      watermark = Familia.now.to_i
      @matrix_customer.last_password_update!(watermark)
      rewrite_session_blob { |blob| blob['authenticated_at'] = watermark - 1 }
    when :tenant_surface_mismatch
      rewrite_session_blob do |blob|
        blob[Onetime::SessionSurface::KEY] = { 'kind' => 'custom', 'id' => 'other-tenant' }
      end
    when :authentication_database_unavailable, :customer_storage_unavailable
      # Applied around evaluation/request by with_matrix_state_dependencies.
    else
      raise ArgumentError, "unknown matrix state: #{state}"
    end
  end

  def with_matrix_state_dependencies(state)
    case state
    when :authentication_database_unavailable
      allow(Auth::Database).to receive(:connection)
        .and_raise(Sequel::DatabaseConnectionError, 'session matrix simulated outage')
    when :customer_storage_unavailable
      allow(Onetime::Customer).to receive(:find_by_extid)
        .and_raise(Redis::ConnectionError, 'session matrix simulated customer-store outage')
    end
    yield
  ensure
    case state
    when :authentication_database_unavailable
      allow(Auth::Database).to receive(:connection).and_call_original
    when :customer_storage_unavailable
      allow(Onetime::Customer).to receive(:find_by_extid).and_call_original
    end
  end

  def public_surface?(surface)
    %i[hydrated_html bootstrap].include?(surface)
  end

  # Hydration and GET /bootstrap/me: always 200, never a refusal code, and the
  # status with both of its projections in agreement (#4462).
  def expect_public_observation(observation, expectation)
    expect(observation[:status]).to eq(200)
    expect(observation[:refusal_code]).to be_nil
    expect(observation[:cache_control]).to eq('private, no-store')
    expect(observation[:session_id_exposed]).to be(false)

    auth_status = expectation.fetch(:auth_status)
    expect(observation[:auth_status]).to eq(auth_status)
    expect(observation[:authenticated]).to be(auth_status == 'authenticated')
    expect(observation[:awaiting_mfa]).to be(auth_status == 'mfa_pending')

    expect_snapshot_ordering(observation, expectation.fetch(:ordered))

    case expectation.fetch(:public)
    when :anonymous
      expect(observation).to include(customer_exposed: false, identity_exposed: false)
    when :mfa_pending
      expect(observation).to include(customer_exposed: false, identity_exposed: false)
      expect(observation.fetch(:payload)).to include(MFA_PROTECTED_ACCOUNT_FIELDS)
    when :identity_exposed
      expect(observation).to include(customer_exposed: true, identity_exposed: true)
    else
      raise ArgumentError, "unknown public verdict: #{expectation.fetch(:public)}"
    end
  end

  # ADR-046: the pair labels a snapshot that reports a session, and is OMITTED
  # (never null) from one that does not. A session end therefore reaches the
  # client as a plain unordered payload whatever happened to the counter.
  def expect_snapshot_ordering(observation, ordered)
    if ordered
      expect(observation[:snapshot_epoch]).to match(/\A[0-9a-f]{32}\z/)
      expect(observation[:snapshot_version]).to match(/\A[1-9][0-9]*\z/)
      expect(observation[:snapshot_keys]).to eq(%w[snapshot_epoch snapshot_generated_at snapshot_version])
    else
      expect(observation[:snapshot_keys]).to eq([])
    end
  end

  # Protected HTML and the protected API. The status, the redirect, and the
  # pre-#4462 body fields are asserted unchanged; `code` / `code_scope` are
  # additive, and only on the JSON refusal.
  def expect_protected_observation(observation, expectation, surface)
    case expectation.fetch(:protected)
    when :refused
      expect(observation).to include(identity_exposed: false, customer_exposed: false)

      if surface == :protected_html
        expect(observation[:status]).to eq(302)
        expect(observation[:refusal_code]).to be_nil
        expect(observation[:refusal_body]).to be_nil
      else
        expect(observation[:status]).to eq(401)
        expect(observation[:refusal_code]).to eq(expectation.fetch(:code))
        # `message` is NOT the session marker on this route. /api/account/ is
        # `auth=sessionauth,basicauth`, and Otto renders the LAST failure in
        # the chain: basicauth's, which for a browser is always the missing
        # header. Before #4462 that made every session refusal on the API
        # indistinguishable on the wire; `code` is what carries the typed
        # verdict across. The session marker is still asserted, from the
        # strategy itself, through observation[:refusal_markers].
        expect(observation[:refusal_body]).to include(
          'error' => 'Authentication Required',
          'message' => '[AUTH_HEADER_MISSING] No authorization header',
          'timestamp' => a_kind_of(Integer),
          'code' => expectation.fetch(:code),
          'code_scope' => expectation.fetch(:scope),
        )
        expect(observation[:refusal_body].keys).to contain_exactly(
          'error', 'message', 'timestamp', 'code', 'code_scope'
        )
      end
    when :authenticated
      expect(observation[:status]).to eq(200)
      expect(observation[:refusal_code]).to be_nil
      expect(observation).to include(identity_exposed: true, customer_exposed: true)
    else
      raise ArgumentError, "unknown protected verdict: #{expectation.fetch(:protected)}"
    end
  end

  def anonymous_probe_customer
    Struct.new(:email, :extid).new('matrix-absent@example.invalid', 'matrix-absent')
  end
end
