# apps/api/v1/controllers/helpers.rb

require_relative '../../../../lib/onetime/helpers/session_helpers'
require_relative '../../../../lib/onetime/helpers/shrimp_helpers'

module V1
  unless defined?(V1::BADAGENTS)
    BADAGENTS     = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
    LOCAL_HOSTS   = ['localhost', '127.0.0.1'].freeze  # TODO: Add config
    HEADER_PREFIX = ENV.fetch('HEADER_PREFIX', 'X_SECRET_').upcase
  end

  module ControllerHelpers
    include Onetime::Helpers::SessionHelpers
    include Onetime::Helpers::ShrimpHelpers
    # `carefully` is a wrapper around the main web application logic. We
    # handle errors, redirects, and other exceptions here to ensure that
    # we respond consistently to all requests. That's why we integrate
    # Sentry here rather than app specific logic.
    def carefully(redirect = nil, content_type = nil, app: :web) # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
      redirect     ||= req.request_path unless app == :api
      content_type ||= 'text/html; charset=utf-8'

      cust ||= V1::Customer.anonymous

      # Prevent infinite redirect loops by checking if the request is a GET request.
      # Pages redirecting from a POST request can use the same page once.
      if req.get? && redirect.to_s == req.request_path
        redirect = '/500'
      end

      # Generate a unique nonce for this response
      nonce = SecureRandom.base64(16)

      # Make the nonce available to the CSP header
      add_response_headers(content_type, nonce)

      # Make the nonce available to the view
      req.env['ots.nonce'] = nonce

      return_value = yield

      log_customer_activity

      obscured = if cust.anonymous?
        'anonymous'
      else
        OT::Utils.obscure_email(cust.custid)
      end

      return_value
    rescue OT::Redirect => ex
      OT.info "[carefully] Redirecting to #{ex.location} (#{ex.status})"
      res.redirect ex.location, ex.status
    rescue OT::Unauthorized => ex
      OT.info ex.message
      not_authorized_error
    rescue Onetime::BadShrimp
      # If it's a json response, no need to set an error message on the session
      if res.headers['content-type'] == 'application/json'
        error_response 'Please refresh the page and try again', reason: 'Bad shrimp 🍤'
      else
        session['error_message'] = 'Please go back, refresh the page, and try again.'
        res.redirect redirect
      end
    rescue OT::FormError => ex
      OT.ld "[carefully] FormError: #{ex.message} (#{req.path}) redirect:#{redirect || 'n/a'}"

      # Track form errors in Sentry. They can indicate bugs that would
      # not surface any other way. We track as messages though since
      # they are not exceptions in the diagnostic sense. We pass only
      # the message and not fields to limit the amount of data sent.
      capture_message ex.message, :error

      if redirect
        handle_form_error ex, redirect
      else
        handle_form_error ex
      end

    # NOTE: It's important to handle MissingSecret before RecordNotFound since
    #       MissingSecret is a subclass of RecordNotFound. If we don't, we'll
    #       end up with a generic error message instead of the specific one.
    rescue OT::MissingSecret
      secret_not_found_response
    rescue OT::RecordNotFound => ex
      OT.ld "[carefully] RecordNotFound: #{ex.message} (#{req.path}) redirect:#{redirect || 'n/a'}"
      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      not_found_response ex.message, shrimp: (respond_to?(:shrimp_token) ? shrimp_token : nil)
    rescue Familia::HighRiskFactor => ex
      session_id = session.id&.to_s || req.cookies['onetime.session'] || 'unknown'
      short_session_id = session_id.length <= 10 ? session_id : session_id[0, 10] + '...'
      OT.le "[attempt-saving-non-string-to-db] #{obscured} (#{req.client_ipaddress}): #{short_session_id} (#{req.current_absolute_uri})"

      # Track attempts to save non-string data to the database as a warning error
      capture_error ex, :warning

      # Include fresh shrimp so they can try again 🦐
      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      error_response "We're sorry, but we can't process your request at this time.", shrimp: (respond_to?(:shrimp_token) ? shrimp_token : nil)
    rescue Familia::NotConnected, Familia::Problem => ex
      OT.le "#{ex.class}: #{ex.message}"
      OT.le ex.backtrace

      # Track Familia errors as regular exceptions
      capture_error ex

      # Include fresh shrimp so they can try again 🦐
      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      error_response 'An error occurred :[', shrimp: (respond_to?(:shrimp_token) ? shrimp_token : nil)
    rescue Errno::ECONNREFUSED => ex
      OT.le ex.message
      OT.le ex.backtrace

      # Track DB connection errors as fatal errors
      capture_error ex, :fatal

      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      error_response "We'll be back shortly!", shrimp: (respond_to?(:shrimp_token) ? shrimp_token : nil)
    rescue StandardError => ex
      custid = cust&.custid || '<notset>'
      session_id = session.id&.to_s || req.cookies['onetime.session'] || 'unknown'
      short_session_id = session_id.length <= 10 ? session_id : session_id[0, 10] + '...'
      OT.le "#{ex.class}: #{ex.message} -- #{req.current_absolute_uri} -- #{req.client_ipaddress} #{custid} #{short_session_id} #{locale} #{content_type} #{redirect} "
      OT.le ex.backtrace.join("\n")

      # Track the unexected errors
      capture_error ex

      regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      error_response 'An unexpected error occurred :[', shrimp: (respond_to?(:shrimp_token) ? shrimp_token : nil)
    ensure
      @sess ||= V1::Session.new 'failover', 'anon'
      @cust ||= V1::Customer.anonymous
    end

    # Sets the locale for the request based on various sources.
    #
    # This method determines the locale to be used for the request by checking
    # the following sources in order of precedence:
    # 1. The `locale` argument passed to the method.
    # 2. The `locale` query parameter in the request.
    # 3. The customer's previously saved preferred locale (if customer exists).
    # 4. The `rack.locale` environment variable set by Otto.
    #
    # If a valid locale is found in any of these sources, it is set in the
    # `req.env['ots.locale']` environment variable. If no valid locale is found,
    # the default locale from the configuration is used.
    #
    # @param locale [String, nil] The locale to be used, if specified.
    # @return [void]
    def check_locale!(locale = nil)
      locale ||= req.params[:locale]
      locale ||= cust.locale if cust&.locale
      locale ||= (req.env['rack.locale'] || []).first

      have_translations = locale && OT.locales.has_key?(locale)
      lmsg              = format(
        '[check_locale!] class=%s locale=%s cust=%s req=%s t=%s',
        self.class.name,
        locale,
        cust&.locale,
        req.params.keys,
        have_translations,
      )
      OT.ld lmsg

      # Set the locale in the request environment if it is
      # valid, otherwise use the default locale.
      req.env['ots.locale'] = have_translations ? locale : OT.default_locale

      # Important! This sets the locale for the current request which
      # gets passed through to the logic class along with sess, cust.
      # Without it, emails will be sent in the default locale.
      @locale = req.env['ots.locale']
    end

    def add_response_headers(content_type, nonce)
      # Set the Content-Type header if it's not already set by the application
      res.headers['content-type'] ||= content_type

      # Skip the Content-Security-Policy header if it's already set
      return if res.headers['content-security-policy']

      # Skip the CSP header unless it's enabled in the experimental settings
      return if OT.conf.dig('experimental', 'csp', 'enabled') != true

      # Skip the Content-Security-Policy header if the front is running in
      # development mode. We need to allow inline scripts and styles for
      # hot reloading to work.
      csp = if OT.conf.dig('development', 'enabled')
        [
          "default-src 'none';",                               # Restrict to same origin by default
          "script-src 'unsafe-inline' 'nonce-#{nonce}';",      # Allow Vite's dynamic module imports and source maps
          "style-src 'self' 'unsafe-inline';",                 # Enable Vite's dynamic style injection
          "connect-src 'self' ws: wss: http: https:;",         # Allow WebSocket connections for hot module replacement
          "img-src 'self' data:;",                             # Allow images from same origin only
          "font-src 'self';",                                  # Allow fonts from same origin only
          "object-src 'none';",                                # Block <object>, <embed>, and <applet> elements
          "base-uri 'self';",                                  # Restrict <base> tag targets to same origin
          "form-action 'self';",                               # Restrict form submissions to same origin
          "frame-ancestors 'none';",                           # Prevent site from being embedded in frames
          "manifest-src 'self';",
          # "require-trusted-types-for 'script';",
          "worker-src 'self';",                                # Allow Workers from same origin only
        ]
      else
        [
          "default-src 'none';",
          "script-src 'unsafe-inline' 'nonce-#{nonce}';",      # unsafe-inline is ignored with a nonce
          "style-src 'self' 'unsafe-inline';",
          "connect-src 'self' wss: https:;",                   # Only HTTPS and secure WebSockets
          "img-src 'self' data:;",
          "font-src 'self';",
          "object-src 'none';",
          "base-uri 'self';",
          "form-action 'self';",
          "frame-ancestors 'none';",
          "manifest-src 'self';",
          # "require-trusted-types-for 'script';",
          "worker-src 'self';",
        ]
      end

      OT.ld "[CSP] #{csp.join(' ')}" if OT.debug?

      res.headers['content-security-policy'] = csp.join(' ')
    end

    # Collectes request details in a single string for logging purposes.
    #
    # This method collects the IP address, request method, path, query string,
    # and proxy header details from the given request object and formats them
    # into a single string. The resulting string is suitable for logging.
    #
    # @param req [Rack::Request] The request object containing the details to be
    #   stringified.
    # @return [String] A single string containing the formatted request details.
    #
    # @example
    #   req = Rack::Request.new(env)
    #   stringify_request_details(req)
    #   # => "192.0.2.1; GET /path?query=string; Proxy[HTTP_X_FORWARDED_FOR=203.0.113.195 REMOTE_ADDR=192.0.2.1]"
    #
    def stringify_request_details(req)
      header_details = collect_proxy_header_details(req.env)

      details = [
        req.ip,
        "#{req.request_method} #{req.path_info}?#{req.query_string}",
        "Proxy[#{header_details}]",
      ]

      # Convert the details array to a string for logging
      details.join('; ')
    end

    # Collects and formats specific HTTP header details from the given
    # environment hash, including Cloudflare-specific headers.
    #
    # @param env [Hash, nil] The environment hash containing HTTP headers.
    #   Defaults to an empty hash if not provided.
    # @param keys [Array<String>, nil] The list of HTTP header keys to collect.
    #   Defaults to a predefined list of common proxy-related headers if not
    #   provided.
    # @return [String] A single string with the requested headers formatted as
    #   "key=value" pairs, separated by spaces.
    #
    # @example
    #   env = {
    #     "HTTP_X_FORWARDED_FOR" => "203.0.113.195",
    #     "REMOTE_ADDR" => "192.0.2.1",
    #     "CF-Connecting-IP" => "203.0.113.195",
    #     "CF-IPCountry" => "NL",
    #     "CF-Ray" => "1234567890abcdef",
    #     "CF-Visitor" => "{\"scheme\":\"https\"}"
    #   }
    #   collect_proxy_header_details(env)
    #   # => "HTTP_X_FORWARDED_FOR=203.0.113.195 REMOTE_ADDR=192.0.2.1 CF-Connecting-IP=203.0.113.195 CF-IPCountry=US CF-Ray=1234567890abcdef CF-Visitor={\"scheme\":\"https\"}"
    #
    def collect_proxy_header_details(env = nil, keys = nil)
      env  ||= {}
      keys ||= %w[
        HTTP_FLY_REQUEST_ID
        HTTP_VIA
        HTTP_X_FORWARDED_PROTO
        HTTP_X_FORWARDED_FOR
        HTTP_X_FORWARDED_HOST
        HTTP_X_FORWARDED_PORT
        HTTP_X_SCHEME
        HTTP_X_REAL_IP
        HTTP_CF_IPCOUNTRY
        HTTP_CF_RAY
        REMOTE_ADDR
      ]

      # Add any header that begins with HEADER_PREFIX
      prefix_keys = env.keys.select { |key| key.upcase.start_with?("HTTP_#{HEADER_PREFIX}") }
      keys.concat(prefix_keys) # the bang is silent

      keys.sort.map do |key|
        # Normalize the header name so it looks identical in the logs as it
        # does in the browser dev console.
        #
        # e.g. Content-Type instead of HTTP_CONTENT_TYPE
        #
        pretty_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
        "#{pretty_name}: #{env[key]}"
      end.join(' ')
    end

    def secure?
      # It's crucial to only accept header values set by known, trusted
      # sources. See Caddy config docs re: trusted_proxies.
      # X-Scheme is set by e.g. nginx, caddy etc
      # X-FORWARDED-PROTO is set by load balancer e.g. ELB
      (req.env['HTTP_X_FORWARDED_PROTO'] == 'https' || req.env['HTTP_X_SCHEME'] == 'https')
    end


    def deny_agents! *_agents
      BADAGENTS.flatten.each do |agent|
        if req.user_agent =~ /#{agent}/i
          raise OT::Redirect.new('/')
        end
      end
    end

    def no_cache!
      res.headers['cache-control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      res.headers['expires']       = 'Mon, 7 Nov 2011 00:00:00 UTC'
      res.headers['pragma']        = 'no-cache'
    end

    def app_path *paths
      paths = paths.flatten.compact
      paths.unshift req.script_name
      paths.join('/').gsub '//', '/'
    end

    def setup_request_context
      return if @request_context_setup

      @request_context_setup = true

      # Session is already loaded by Rack::Session::RedisFamilia middleware
      # Load customer based on session state
      @cust = current_customer

      # Track request for security monitoring
      unless @cust.anonymous?
        custref = @cust.obscure_email
        OT.ld "[session.request] #{custref} #{request.request_method} #{request.path}"
      end
    end

    # Check CSRF value submitted with POST requests (aka shrimp)
    def check_shrimp!(_replace = true)
      return if @check_shrimp_ran

      @check_shrimp_ran = true
      return unless state_changing_request?

      # Extract token from request
      token = extract_shrimp_token

      # Verify using the modern shrimp helpers
      verify_shrimp!(token) if token
    end


    # Checks if authentication is enabled for the site.
    #
    # This method determines whether authentication is enabled by checking the
    # site configuration. It defaults to disabled if the site configuration is
    # missing. This approach prevents unauthorized access by ensuring that
    # accounts are not used if authentication is not explicitly enabled.
    #
    # @return [Boolean] True if authentication and sign-in are enabled, false otherwise.
    #
    def authentication_enabled?
      # Defaulting to disabled is the Right Thing to Do™. If the site config
      # is missing, we assume that authentication is disabled and that accounts
      # are not used. This prevents situations where the app is running and
      # anyone accessing it can create an account without proper authentication.
      authentication_enabled = OT.conf['site']['authentication']['enabled'] rescue false # rubocop:disable Style/RescueModifier
      signin_enabled         = OT.conf['site']['authentication']['signin'] rescue false # rubocop:disable Style/RescueModifier

      # The only condition that allows a request to be authenticated is if
      # the site has authentication enabled, and the user is signed in. If a
      # user is signed in and the site configuration changes to disable it,
      # the user will be signed out temporarily. If the setting is restored
      # before the session key expires in Redis, that user will be signed in
      # again. This is a security feature.
      authentication_enabled && signin_enabled
    end

    def log_customer_activity
      return if cust.anonymous?

      reqstr  = stringify_request_details(req)
      custref = cust.obscure_email
      session_id = session.id&.to_s || req.cookies['onetime.session'] || 'unknown'
      short_session_id = session_id.length <= 10 ? session_id : session_id[0, 10] + '...'
      OT.info "[carefully] #{short_session_id} #{custref} at #{reqstr}"
    end

    # Sentry terminology:
    #   - An event is one instance of sending data to Sentry. Generally, this
    #   data is an error or exception.
    #   - An issue is a grouping of similar events.
    #   - Capturing is the act of reporting an event.
    #
    # Available levels are :fatal, :error, :warning, :log, :info,
    # and :debug. The Sentry default, if not specified, is :error.
    #
    def capture_error(error, level = :error, &)
      return unless OT.d9s_enabled # diagnostics are disabled by default

      # Capture more detailed debugging information when Sentry errors occur
      begin
        # Log request headers before attempting to send to Sentry
        if defined?(req) && req.respond_to?(:env)
          headers = req.env.select { |k, _v| k.start_with?('HTTP_') rescue false } # rubocop:disable Style/RescueModifier
          OT.ld "[capture_error] Request headers: #{headers.inspect}"
        end

        # Try Sentry exception reporting
        Sentry.capture_exception(error, level: level, &)
      rescue NoMethodError => ex
        raise unless ex.message.include?('start_with?')

        # Continue execution - don't let a Sentry error break the app
        OT.le "[capture_error] Sentry error with nil value in start_with? check: #{ex.message}"
        OT.ld ex.backtrace.join("\n")

      # Re-raise any other NoMethodError that isn't related to start_with?
      rescue StandardError => ex
        OT.le "[capture_error] #{ex.class}: #{ex.message}"
        OT.ld ex.backtrace.join("\n")
      end
    end

    def capture_message(message, level = :log, &)
      return unless OT.d9s_enabled # diagnostics are disabled by default

      Sentry.capture_message(message, level: level, &)
    rescue StandardError => ex
      OT.le "[capture_message] #{ex.class}: #{ex.message}"
      OT.ld ex.backtrace.join("\n")
    end
  end
end
