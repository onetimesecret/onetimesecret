# etc/init.d/rack_attack.rb
#
# Minimal update to work with OneTime Secret's custom session system.
# This version just replaces the session access logic with minimal changes.

class Rack::Attack

  ### Configure Cache ###

  # Configure cache store for OneTime Secret (pure Rack app)
  # Use Redis for consistency with your existing session storage
  # Note: The store is only used for throttling (not blocklisting and
  # safelisting). It must implement .increment and .write

  # Use your existing Redis connection
  Rack::Attack.cache.store = Rack::Attack::StoreProxy::RedisStoreProxy.new(Familia.redis(0))

  ### Helper Method to Extract Session ID ###

  # Extract session ID from OneTime Secret's custom session cookie
  def self.get_session_identifier(req)
    # Get the session cookie value (OneTime Secret uses 'sess' cookie)
    session_cookie = req.cookies['sess']

    if session_cookie && session_cookie.match?(/\A[a-z0-9]{40,60}\z/)
      # Use session ID if valid
      session_cookie
    else
      # Fallback to IP (handle CloudFlare proxying)
      req.env['HTTP_CF_CONNECTING_IP'] || req.ip
    end
  end

  ### CloudFlare IP Handling ###

  # IMPORTANT: When using CloudFlare, req.ip will be CloudFlare's IP address
  # rather than the actual client IP. To get the real client IP, you should:
  # 1. Configure your app to trust CloudFlare's CF-Connecting-IP header
  # 2. Use trusted proxies configuration in your app
  # 3. Consider using session-based limiting as fallback (as done below)
  #
  # Example of getting real IP through CloudFlare:
  # real_ip = req.env['HTTP_CF_CONNECTING_IP'] || req.ip
  #
  # For now, we prioritize session-based limiting when available, falling
  # back to IP-based limiting for requests without sessions.

  ### General Request Throttling ###

  # General page requests - equivalent to :get_page and :dashboard
  throttle('general/pages', limit: 1000, period: 20.minutes) do |req|
    # Use session identifier when available, fallback to IP
    # Note: IP may be CloudFlare's due to proxying
    get_session_identifier(req) if req.get? && !req.path.start_with?('/assets')
  end

  # API status checks - equivalent to :check_status
  throttle('api/status', limit: 10000, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?status})
  end

  ### Secret Operations ###

  # Secret creation - equivalent to :create_secret
  # Example URIs that match:
  # POST /secret
  # POST /api/secret
  throttle('secrets/create', limit: 1000, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?secret})
  end

  # Secret viewing - equivalent to :show_secret and :show_metadata
  throttle('secrets/view', limit: 1000, period: 20.minutes) do |req|
    get_session_identifier(req) if req.get? && req.path.match?(%r{/(api/v\d/)?secret/[^/]+})
  end

  # Secret burning - equivalent to :burn_secret
  throttle('secrets/burn', limit: 1000, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?secret/[^/]+/burn})
  end

  # Failed passphrase attempts - equivalent to :failed_passphrase
  throttle('secrets/failed_passphrase', limit: 5, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?secret/[^/]+}) && req.params['passphrase']
  end

  # Secret access attempts - equivalent to :attempt_secret_access
  throttle('secrets/access_attempts', limit: 10, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?secret/[^/]+}) && (req.get? || req.post?)
  end

  ### Account Operations ###

  # Account creation - equivalent to :create_account
  throttle('accounts/create', limit: 10, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?signup})
  end

  # Account updates - equivalent to :update_account
  throttle('accounts/update', limit: 10, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?account})
  end

  # Account deletion - equivalent to :destroy_account
  throttle('accounts/destroy', limit: 2, period: 20.minutes) do |req|
    get_session_identifier(req) if req.delete? && req.path.match?(%r{/(api/v\d/)?account})
  end

  # Account viewing - equivalent to :show_account
  throttle('accounts/show', limit: 100, period: 20.minutes) do |req|
    get_session_identifier(req) if req.get? && req.path.match?(%r{/(api/v\d/)?account})
  end

  ### Authentication ###

  # Session authentication - equivalent to :authenticate_session
  throttle('auth/login', limit: 5, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?signin})
  end

  # Session destruction - equivalent to :destroy_session
  throttle('auth/logout', limit: 5, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?signout})
  end

  # Password reset requests - equivalent to :forgot_password_request
  throttle('auth/forgot_password_request', limit: 2, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?forgot})
  end

  # Password reset attempts - equivalent to :forgot_password_reset
  throttle('auth/forgot_password_reset', limit: 3, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?reset})
  end

  ### API Token Operations ###

  # API token generation - equivalent to :generate_apitoken
  throttle('api/token_generation', limit: 10, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?apitoken})
  end

  ### Domain Operations ###

  # Domain management - equivalent to :add_domain, :remove_domain, :verify_domain
  throttle('domains/management', limit: 30, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?domain})
  end

  # Domain listing/viewing - equivalent to :list_domains, :get_domain
  throttle('domains/viewing', limit: 100, period: 20.minutes) do |req|
    get_session_identifier(req) if req.get? && req.path.match?(%r{/(api/v\d/)?domain})
  end

  # Domain branding - equivalent to :update_branding, :get_domain_brand, :update_domain_brand
  throttle('domains/branding', limit: 50, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?domain/[^/]+/(brand|logo)})
  end

  ### Email Operations ###

  # Email sending - equivalent to :email_recipient
  throttle('email/send', limit: 50, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.params['recipient']
  end

  ### Feedback and Support ###

  # Feedback submission - equivalent to :send_feedback
  throttle('feedback/send', limit: 10, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?feedback})
  end

  # Exception reporting - equivalent to :report_exception
  throttle('errors/report', limit: 50, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?error})
  end

  ### Colonel (Admin) Operations ###

  # Colonel viewing - equivalent to :view_colonel
  throttle('colonel/view', limit: 100, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?colonel})
  end

  # Colonel settings updates - equivalent to :update_colonel_settings
  throttle('colonel/update', limit: 50, period: 20.minutes) do |req|
    get_session_identifier(req) if req.post? && req.path.match?(%r{/(api/v\d/)?colonel})
  end

  ### External Services ###

  # External redirects - equivalent to :external_redirect
  throttle('external/redirect', limit: 100, period: 20.minutes) do |req|
    get_session_identifier(req) if req.path.match?(%r{/(api/v\d/)?redirect})
  end

  # Stripe webhooks - equivalent to :stripe_webhook
  throttle('webhooks/stripe', limit: 25, period: 20.minutes) do |req|
    req.ip if req.post? && req.path.match?(%r{/(api/v\d/)?webhook/stripe})
  end

  # Image serving - equivalent to :get_image, :get_domain_logo
  throttle('assets/images', limit: 1000, period: 20.minutes) do |req|
    get_session_identifier(req) if req.get? && req.path.match?(%r{\.(png|jpg|jpeg|gif|svg)$})
  end

  throttle('general/pages', limit: 1000, period: 20.minutes) do |req|
    # Use session identifier when available, fallback to IP
    # Note: IP may be CloudFlare's due to proxying
    get_session_identifier(req) if req.get?
  end

  ### Custom Throttle Response ###

  # Return a custom response for throttled requests
  self.throttled_responder = lambda do |env|
    [429, {'Content-Type' => 'application/json'}, ['{"error": "Rate limit exceeded. Please try again later."}']]
  end

end

module SimpleNotifications
  class << self
    def subscribe(pattern, &block)
      subscribers[pattern] ||= []
      subscribers[pattern] << block
    end

    def instrument(name, payload = {})
      start_time = Time.now
      yield if block_given?
      finish_time = Time.now

      matching_subscribers(name).each do |subscriber|
        subscriber.call(name, start_time, finish_time, SecureRandom.uuid, payload)
      end
    end

    private

    def subscribers
      @subscribers ||= {}
    end

    def matching_subscribers(name)
      subscribers.select { |pattern, _| pattern === name }.flat_map { |_, subs| subs }
    end
  end
end

SimpleNotifications.subscribe(/rack_attack/) do |name, start, finish, request_id, payload|
  # request object available in payload[:request]
  puts payload[:request].inspect
  # Your code here
end
