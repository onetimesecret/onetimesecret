# apps/api/v1/controllers/helpers.rb

require_relative '../plan'

module V1

  unless defined?(V1::BADAGENTS)
    BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
    LOCAL_HOSTS = ['localhost', '127.0.0.1'].freeze  # TODO: Add config
    HEADER_PREFIX = ENV.fetch('HEADER_PREFIX', 'X_SECRET_').upcase
  end

  module ControllerHelpers

    def plan
      @plan = V1::Plan.plan(cust.planid) unless cust.nil?
      @plan ||= V1::Plan.plan('anonymous')
      @plan
    end

    # `carefully` is a wrapper around the main web application logic. We
    # handle errors, redirects, and other exceptions here to ensure that
    # we respond consistently to all requests. That's why we integrate
    # Sentry here rather than app specific logic.
    def carefully(redirect=nil, content_type=nil, app: :web) # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
      redirect ||= req.request_path unless app == :api
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
        V1::Utils.obscure_email(cust.custid)
      end

      return_value

    rescue OT::Redirect => ex
      OT.info "[carefully] Redirecting to #{ex.location} (#{ex.status})"
      res.redirect ex.location, ex.status

    rescue OT::Unauthorized => ex
      OT.info ex.message
      not_authorized_error

    rescue Onetime::BadShrimp => ex
      # If it's a json response, no need to set an error message on the session
      if res.headers['content-type'] == 'application/json'
        error_response 'Please refresh the page and try again', reason: "Bad shrimp 🍤"
      else
        sess.set_error_message "Please go back, refresh the page, and try again."
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
    rescue OT::MissingSecret => ex
      secret_not_found_response

    rescue OT::RecordNotFound => ex
      OT.ld "[carefully] RecordNotFound: #{ex.message} (#{req.path}) redirect:#{redirect || 'n/a'}"
      not_found_response ex.message, shrimp: sess.add_shrimp

    rescue OT::LimitExceeded => ex
      msg = "#{ex.event}(#{ex.count}) #{sess.identifier.shorten(10)}"
      OT.le "[limit-exceeded] #{obscured} (#{sess.ipaddress}): #{msg} (#{req.current_absolute_uri})"

      # Track rate limiting as a warning message
      capture_message "#{ex.message}: #{msg}", :warning

      throttle_response "Cripes! You have been rate limited."

    rescue Familia::HighRiskFactor => ex
      OT.le "[attempt-saving-non-string-to-db] #{obscured} (#{sess.ipaddress}): #{sess.identifier.shorten(10)} (#{req.current_absolute_uri})"

      # Track attempts to save non-string data to Redis as a warning error
      capture_error ex, :warning

      # Include fresh shrimp so they can try again 🦐
      error_response "We're sorry, but we can't process your request at this time.", shrimp: sess.add_shrimp

    rescue Familia::NotConnected, Familia::Problem => ex
      OT.le "#{ex.class}: #{ex.message}"
      OT.le ex.backtrace

      # Track Familia errors as regular exceptions
      capture_error ex

      # Include fresh shrimp so they can try again 🦐
      error_response "An error occurred :[", shrimp: sess ? sess.add_shrimp : nil

    rescue Errno::ECONNREFUSED => ex
      OT.le ex.message
      OT.le ex.backtrace

      # Track DB connection errors as fatal errors
      capture_error ex, :fatal

      error_response "We'll be back shortly!", shrimp: sess ? sess.add_shrimp : nil

    rescue StandardError => ex
      custid = cust&.custid || '<notset>'
      sessid = sess&.short_identifier || '<notset>'
      OT.le "#{ex.class}: #{ex.message} -- #{req.current_absolute_uri} -- #{req.client_ipaddress} #{custid} #{sessid} #{locale} #{content_type} #{redirect} "
      OT.le ex.backtrace.join("\n")

      # Track the unexected errors
      capture_error ex

      error_response "An unexpected error occurred :[", shrimp: sess ? sess.add_shrimp : nil

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
      locales = OT.conf['locales']

      have_translations = locale && locales.has_key?(locale)
      lmsg = format(
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
      req.env['ots.locale'] = have_translations ? locale : OT.conf[:default_locale]

      # Important! This sets the locale for the current request which
      # gets passed through to the logic class along with sess, cust.
      # Without it, emails will be sent in the default locale.
      @locale = req.env['ots.locale']
    end

    # Check CSRF value submitted with POST requests (aka shrimp)
    #
    # Note: This method is called only for session authenticated
    # requests. Requests via basic auth (/api), may check for a
    # valid shrimp, but they don't regenerate a fresh every time
    # a successful validation occurs.
    def check_shrimp!(replace=true)
      return if @check_shrimp_ran
      @check_shrimp_ran = true
      return unless req.post? || req.put? || req.delete? || req.patch?

      # Check for shrimp in params and in the O-Shrimp header
      header_shrimp = (req.env['HTTP_O_SHRIMP'] || req.env['HTTP_ONETIME_SHRIMP']).to_s
      params_shrimp = req.params[:shrimp].to_s

      # Use the header shrimp if it's present, otherwise use the param shrimp
      attempted_shrimp = header_shrimp.empty? ? params_shrimp : header_shrimp

      # No news is good news for successful shrimp; by default
      # it'll simply add a fresh shrimp to the session. But
      # in the case of failure this will raise an exception.
      validate_shrimp(attempted_shrimp)
    end

    def validate_shrimp(attempted_shrimp, replace=true)
      shrimp_is_empty = attempted_shrimp.empty?
      log_value = attempted_shrimp.shorten(5)

      if sess.shrimp?(attempted_shrimp) || ignoreshrimp
        adjective = ignoreshrimp ? 'IGNORED' : 'GOOD'
        OT.ld "#{adjective} SHRIMP for #{cust.custid}@#{req.path}: #{log_value}"
        # Regardless of the outcome, we clear the shrimp from the session
        # to prevent replay attacks. A new shrimp is generated on the
        # next page load.
        sess.replace_shrimp! if replace
        true
      else
        ### NOTE: MUST FAIL WHEN NO SHRIMP OTHERWISE YOU CAN
        ### JUST SUBMIT A FORM WITHOUT ANY SHRIMP WHATSOEVER
        ### AND THAT'S NO WAY TO TREAT A GUEST.
        shrimp = (sess.shrimp || '[noshrimp]').clone
        ex = Onetime::BadShrimp.new(req.path, cust.custid, attempted_shrimp, shrimp)
        OT.ld "BAD SHRIMP for #{cust.custid}@#{req.path}: #{log_value}"
        sess.replace_shrimp! if replace && !shrimp_is_empty
        raise ex
      end
    end
    protected :validate_shrimp

    def check_session!
      return if @check_session_ran
      @check_session_ran = true

      # Load from the db or create the session
      if req.cookie?(:sess) && V1::Session.exists?(req.cookie(:sess))
        @sess = V1::Session.load req.cookie(:sess)
      else
        @sess = V1::Session.create req.client_ipaddress, "anon", req.user_agent
      end

      # Set the session to rack.session
      #
      # The `req.env` hash is a central repository for all environment variables
      # and request-specific data in a Rack application. By setting the session
      # object in `req.env['rack.session']`, we make the session data accessible
      # to all middleware and components that process the request and response.
      # This approach ensures that the session data is consistently available
      # throughout the entire request-response cycle, allowing middleware to
      # read from and write to the session as needed. This is particularly
      # useful for maintaining user state, managing authentication, and storing
      # other session-specific information.
      #
      # Example:
      #   If a middleware needs to check if a user is authenticated, it can
      #   access the session data via `env['rack.session']` and perform the
      #   necessary checks or updates.
      #
      req.env['rack.session'] = sess

      # Immediately check the the auth status of the session. If the site
      # configuration changes to disable authentication, the session will
      # report as not authenticated regardless of the session data.
      #
      # NOTE: The session keys have their own dedicated Redis DB, so they
      # can be flushed to force everyone to logout without affecting the
      # rest of the data. This is a security feature.
      sess.disable_auth = !authentication_enabled?

      # Update the session fields in the database (including updated timestamp)
      sess.save

      # Only set the cookie after session is for sure saved to the database
      is_secure = Onetime.conf&.dig(:site, :ssl)

      # Update the session cookie
      res.send_cookie :sess, sess.sessid, sess.ttl, is_secure

      # Re-hydrate the customer object
      @cust = sess.load_customer || V1::Customer.anonymous

      # We also force the session to be unauthenticated based on
      # the customer object.
      if cust.anonymous?
        sess.authenticated = false
      elsif cust.verified.to_s != 'true'
        sess.authenticated = false
      end

      # Should always report false and false when disabled.
      unless cust.anonymous?
        custref = cust.obscure_email
        OT.ld "[sess.check_session(v1)] #{sess.short_identifier} #{custref} authenabled=#{authentication_enabled?.to_s}, sess=#{sess.authenticated?.to_s}"
      end
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
      signin_enabled = OT.conf['site']['authentication']['signin'] rescue false # rubocop:disable Style/RescueModifier

      # The only condition that allows a request to be authenticated is if
      # the site has authentication enabled, and the user is signed in. If a
      # user is signed in and the site configuration changes to disable it,
      # the user will be signed out temporarily. If the setting is restored
      # before the session key expires in Redis, that user will be signed in
      # again. This is a security feature.
      authentication_enabled && signin_enabled
    end

    def add_response_headers(content_type, nonce)
      # Set the Content-Type header if it's not already set by the application
      res.headers['content-type'] ||= content_type

      # Skip the Content-Security-Policy header if it's already set
      return if res.headers['Content-Security-Policy']

      # Skip the CSP header unless it's enabled in the experimental settings
      return if OT.conf.dig(:experimental, :csp, :enabled) != true

      # Skip the Content-Security-Policy header if the front is running in
      # development mode. We need to allow inline scripts and styles for
      # hot reloading to work.
      if OT.conf.dig(:development, :enabled)
        csp = [
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
        csp = [
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
          #"require-trusted-types-for 'script';",
          "worker-src 'self';",
        ]
      end

      OT.ld "[CSP] #{csp.join(' ')}" if OT.debug?

      res.headers['Content-Security-Policy'] = csp.join(' ')
    end

    def log_customer_activity
      return if cust.anonymous?
      reqstr = stringify_request_details(req)
      custref = cust.obscure_email
      OT.info "[carefully] #{sess.short_identifier} #{custref} at #{reqstr}"
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

    # Sentry terminology:
    #   - An event is one instance of sending data to Sentry. Generally, this
    #   data is an error or exception.
    #   - An issue is a grouping of similar events.
    #   - Capturing is the act of reporting an event.
    #
    # Available levels are :fatal, :error, :warning, :log, :info,
    # and :debug. The Sentry default, if not specified, is :error.
    #
    def capture_error(error, level=:error, &)
      return unless OT.conf[:d9s_enabled] # diagnostics are disabled by default

      # Capture more detailed debugging information when Sentry errors occur
      begin
        # Log request headers before attempting to send to Sentry
        if defined?(req) && req.respond_to?(:env)
          headers = req.env.select { |k, _v| k.start_with?('HTTP_') rescue false } # rubocop:disable Style/RescueModifier
          OT.ld "[capture_error] Request headers: #{headers.inspect}"
        end

        # Try Sentry exception reporting
        Sentry.capture_exception(error, level: level, &)
      rescue NoMethodError => e
        if e.message.include?('start_with?')
          OT.le "[capture_error] Sentry error with nil value in start_with? check: #{e.message}"
          OT.ld e.backtrace.join("\n")
          # Continue execution - don't let a Sentry error break the app
        else
          # Re-raise any other NoMethodError that isn't related to start_with?
          raise
        end
      rescue StandardError => ex
        OT.le "[capture_error] #{ex.class}: #{ex.message}"
        OT.ld ex.backtrace.join("\n")
      end
    end

    def capture_message(message, level=:log, &)
      return unless OT.conf[:d9s_enabled] # diagnostics are disabled by default
      Sentry.capture_message(message, level: level, &)
    rescue StandardError => ex
      OT.le "[capture_message] #{ex.class}: #{ex.message}"
      OT.ld ex.backtrace.join("\n")
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
    def collect_proxy_header_details(env=nil, keys=nil)
      env ||= {}
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

      keys.sort.map { |key|
        # Normalize the header name so it looks identical in the logs as it
        # does in the browser dev console.
        #
        # e.g. Content-Type instead of HTTP_CONTENT_TYPE
        #
        pretty_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
        "#{pretty_name}: #{env[key]}"
      }.join(" ")
    end


    def secure?
      # It's crucial to only accept header values set by known, trusted
      # sources. See Caddy config docs re: trusted_proxies.
      # X-Scheme is set by e.g. nginx, caddy etc
      # X-FORWARDED-PROTO is set by load balancer e.g. ELB
      (req.env['HTTP_X_FORWARDED_PROTO'] == 'https' || req.env['HTTP_X_SCHEME'] == "https")
    end

    def local?
      (LOCAL_HOSTS.member?(req.env['SERVER_NAME']) && (req.client_ipaddress == '127.0.0.1'))
    end

    def deny_agents! *agents
      BADAGENTS.flatten.each do |agent|
        if req.user_agent =~ /#{agent}/i
          raise OT::Redirect.new('/')
        end
      end
    end

    def no_cache!
      res.headers['Cache-Control'] = "no-store, no-cache, must-revalidate, max-age=0"
      res.headers['Expires'] = "Mon, 7 Nov 2011 00:00:00 UTC"
      res.headers['Pragma'] = "no-cache"
    end

    def app_path *paths
      paths = paths.flatten.compact
      paths.unshift req.script_name
      paths.join('/').gsub '//', '/'
    end

  end
end
