# frozen_string_literal: true

require 'json'
require 'nokogiri'

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
      activity: NO_ACTIVE_SESSION,
    },
    revoked: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: NO_ACTIVE_SESSION,
    },
    inactive: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: EXPIRED_ACTIVITY,
    },
    absolute_expired: {
      markers: request_markers('SESSION_REVOKED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: EXPIRED_ACTIVITY,
    },
    legacy_unstamped: {
      markers: request_markers(nil),
      verdict: :authenticated,
      protected: :authenticated,
      public: :identity_exposed,
      activity: NO_ACTIVITY,
    },
    mfa_pending: {
      markers: request_markers('SESSION_AWAITING_MFA'),
      verdict: :mfa_pending,
      protected: :refused,
      public: :mfa_pending,
      activity: NO_ACTIVITY,
    },
    suspended: {
      markers: request_markers('ACCOUNT_SUSPENDED'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: NO_ACTIVITY,
    },
    credential_stale: {
      markers: request_markers('SESSION_STALE_CREDENTIALS'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: NO_ACTIVITY,
    },
    tenant_surface_mismatch: {
      markers: request_markers('SESSION_SURFACE_MISMATCH'),
      verdict: :rejected,
      protected: :refused,
      public: :anonymous,
      activity: NO_ACTIVITY,
    },
    authentication_database_unavailable: {
      markers: request_markers('SESSION_UNVERIFIED'),
      verdict: :unavailable,
      protected: :refused,
      public: :anonymous,
      activity: NO_ACTIVITY,
    },
    customer_storage_unavailable: {
      markers: request_markers('SESSION_UNVERIFIED'),
      verdict: :unavailable,
      protected: :refused,
      public: :anonymous,
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
      customer_exposed: payload ? !payload['cust'].nil? : body.include?(@matrix_customer.extid),
      identity_exposed: body.include?(@matrix_customer.email) || body.include?(@matrix_customer.extid),
      refusal_markers: markers.compact.uniq,
      refusal_code: refusal_code(body),
      request_id: response_request_id(last_response),
    }
  end

  def refusal_code(body)
    parsed = JSON.parse(body)
    parsed['code'] || parsed['error_type'] || parsed['error']
  rescue JSON::ParserError
    body[/\[(?<marker>[A-Z0-9_]+)\]/, :marker]
  end

  def response_request_id(response)
    parsed = JSON.parse(response.body)
    parsed['request_id'] || response.headers['x-request-id'] || response.headers['X-Request-ID']
  rescue JSON::ParserError
    response.headers['x-request-id'] || response.headers['X-Request-ID']
  end

  def capture_activity_writes
    logger = SqlCapture.new
    test_db.loggers << logger
    result = yield
    writes = logger.messages.grep(/\b(?:INSERT|UPDATE|DELETE)\b.*\baccount_active_session_keys\b/i)
    [result, writes]
  ensure
    test_db.loggers.delete(logger) if logger
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
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_raise(Redis::ConnectionError, 'session matrix simulated customer-store outage')
    end
    yield
  ensure
    case state
    when :authentication_database_unavailable
      allow(Auth::Database).to receive(:connection).and_call_original
    when :customer_storage_unavailable
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_call_original
    end
  end

  def anonymous_probe_customer
    Struct.new(:email, :extid).new('matrix-absent@example.invalid', 'matrix-absent')
  end
end
