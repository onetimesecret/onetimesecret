# etc/init.d/rack_attack.rb

class Rack::Attack

  ### Configure Cache ###

  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blocklisting and
  # safelisting). It must implement .increment and .write like
  # ActiveSupport::Cache::Store

  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

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
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.get? && !req.path.start_with?('/assets')
  end

  # API status checks - equivalent to :check_status
  throttle('api/status', limit: 10000, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?status})
  end

  ### Secret Operations ###

  # Secret creation - equivalent to :create_secret
  throttle('secrets/create', limit: 1000, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?secret})
  end

  # Secret viewing - equivalent to :show_secret and :show_metadata
  throttle('secrets/view', limit: 1000, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.get? && req.path.match?(%r{/(api/)?secret/[^/]+})
  end

  # Secret burning - equivalent to :burn_secret
  throttle('secrets/burn', limit: 1000, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?secret/[^/]+/burn})
  end

  # Failed passphrase attempts - equivalent to :failed_passphrase
  throttle('secrets/failed_passphrase', limit: 5, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    # This would need additional logic to detect failed passphrase attempts
    # For now, throttle POST requests to secret endpoints with wrong passphrase
    session_id if req.post? && req.path.match?(%r{/(api/)?secret/[^/]+}) && req.params['passphrase']
  end

  # Secret access attempts - equivalent to :attempt_secret_access
  throttle('secrets/access_attempts', limit: 10, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?secret/[^/]+}) && (req.get? || req.post?)
  end

  ### Account Operations ###

  # Account creation - equivalent to :create_account
  throttle('accounts/create', limit: 10, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?signup})
  end

  # Account updates - equivalent to :update_account
  throttle('accounts/update', limit: 10, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?account})
  end

  # Account deletion - equivalent to :destroy_account
  throttle('accounts/destroy', limit: 2, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.delete? && req.path.match?(%r{/(api/)?account})
  end

  # Account viewing - equivalent to :show_account
  throttle('accounts/show', limit: 100, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.get? && req.path.match?(%r{/(api/)?account})
  end

  ### Authentication ###

  # Session authentication - equivalent to :authenticate_session
  throttle('auth/login', limit: 5, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?signin})
  end

  # Session destruction - equivalent to :destroy_session
  throttle('auth/logout', limit: 5, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?signout})
  end

  # Password reset requests - equivalent to :forgot_password_request
  throttle('auth/forgot_password_request', limit: 2, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?forgot})
  end

  # Password reset attempts - equivalent to :forgot_password_reset
  throttle('auth/forgot_password_reset', limit: 3, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?reset})
  end

  ### API Token Operations ###

  # API token generation - equivalent to :generate_apitoken
  throttle('api/token_generation', limit: 10, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?apitoken})
  end

  ### Domain Operations ###

  # Domain management - equivalent to :add_domain, :remove_domain, :verify_domain
  throttle('domains/management', limit: 30, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?domain})
  end

  # Domain listing/viewing - equivalent to :list_domains, :get_domain
  throttle('domains/viewing', limit: 100, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.get? && req.path.match?(%r{/(api/)?domain})
  end

  # Domain branding - equivalent to :update_branding, :get_domain_brand, :update_domain_brand
  throttle('domains/branding', limit: 50, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?domain/[^/]+/(brand|logo)})
  end

  ### Email Operations ###

  # Email sending - equivalent to :email_recipient
  throttle('email/send', limit: 50, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.params['recipient']
  end

  ### Feedback and Support ###

  # Feedback submission - equivalent to :send_feedback
  throttle('feedback/send', limit: 10, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?feedback})
  end

  # Exception reporting - equivalent to :report_exception
  throttle('errors/report', limit: 50, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?error})
  end

  ### Colonel (Admin) Operations ###

  # Colonel viewing - equivalent to :view_colonel
  throttle('colonel/view', limit: 100, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?colonel})
  end

  # Colonel settings updates - equivalent to :update_colonel_settings
  throttle('colonel/update', limit: 50, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.post? && req.path.match?(%r{/(api/)?colonel})
  end

  ### External Services ###

  # External redirects - equivalent to :external_redirect
  throttle('external/redirect', limit: 100, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.path.match?(%r{/(api/)?redirect})
  end

  # Stripe webhooks - equivalent to :stripe_webhook
  throttle('webhooks/stripe', limit: 25, period: 20.minutes) do |req|
    req.ip if req.post? && req.path.match?(%r{/(api/)?webhook/stripe})
  end

  # Image serving - equivalent to :get_image, :get_domain_logo
  throttle('assets/images', limit: 1000, period: 20.minutes) do |req|
    session_id = req.env['rack.session']&.id || req.ip
    session_id if req.get? && req.path.match?(%r{\.(png|jpg|jpeg|gif|svg)$})
  end

  ### Custom Throttle Response ###

  # Return a custom response for throttled requests
  self.throttled_response = lambda do |env|
    [429, {'Content-Type' => 'application/json'}, ['{"error": "Rate limit exceeded. Please try again later."}']]
  end

end
