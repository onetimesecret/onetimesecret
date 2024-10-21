
module Onetime::App

  unless defined?(Onetime::App::BADAGENTS)
    BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
    LOCAL_HOSTS = ['localhost', '127.0.0.1'].freeze  # TODO: Add config
    HEADER_PREFIX = ENV.fetch('HEADER_PREFIX', 'X_SECRET_').upcase
  end

  module WebHelpers

    attr_reader :req, :res
    attr_reader :sess, :cust, :locale
    attr_reader :ignoreshrimp

    def initialize req, res
      @req, @res = req, res
    end

    def plan
      @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
      @plan ||= Onetime::Plan.plan('anonymous')
      @plan
    end

    def carefully(redirect=nil, content_type=nil, app: :web) # rubocop:disable Metrics/MethodLength
      redirect ||= req.request_path unless app == :api
      content_type ||= 'text/html; charset=utf-8'

      cust ||= OT::Customer.anonymous

      # Determine the locale for the current request
      # We check get here to stop an infinite redirect loop.
      # Pages redirecting from a POST can get by with the same page once.
      redirect = '/500' if req.get? && redirect.to_s == req.request_path

      OT.ld "Checking Content-Language header"
      if res.header['Content-Language']
        OT.ld "Content-Language already set to: #{res.header['Content-Language']}"
      else
        OT.ld "Content-Language not set, determining language"
        content_language = req.env['ots.locale'] || req.env['rack.locale'] || OT.conf[:locales].first
        OT.ld "Selected Content-Language: #{content_language}"
        OT.ld "Source: #{if req.env['ots.locale']
                          'ots.locale'
                          else
                          (req.env['rack.locale'] ? 'rack.locale' : 'OT.conf[:locales].first')
                          end}"
        res.header['Content-Language'] = content_language
        OT.ld "Set Content-Language header to: #{res.header['Content-Language']}"
      end

      res.header['Content-Type'] ||= content_type

      return_value = yield

      unless cust.anonymous?
        reqstr = stringify_request_details(req)
        custref = cust.obscure_email
        OT.info "[carefully] #{sess.short_identifier} #{custref} at #{reqstr}"
      end

      return_value

    rescue OT::Redirect => ex
      OT.info "[carefully] Redirecting to #{ex.location} (#{ex.status})"
      res.redirect ex.location, ex.status

    rescue OT::Unauthorized => ex
      OT.info ex.message
      not_authorized_error

    rescue OT::BadShrimp => ex
      # If it's a json response, no need to set an error message on the session
      if res.header['Content-Type'] == 'application/json'
        error_response 'Please refresh the page and try again'
      else
        sess.set_error_message "Please go back, refresh the page, and try again."
        res.redirect redirect
      end

    rescue OT::FormError => ex
      OT.ld "[carefully] FormError: #{ex.message} (#{req.path} redirect:#{redirect})"
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
      OT.ld "[carefully] RecordNotFound: #{ex.message} (#{req.path} redirect:#{redirect})"
      not_found_response ex.message

    rescue OT::LimitExceeded => ex
      obscured = if cust.anonymous?
                   'anonymous'
                 else
                   OT::Utils.obscure_email(cust.custid)
                 end
      OT.le "[limit-exceeded] #{obscured} (#{sess.ipaddress}): #{ex.event}(#{ex.count}) #{sess.identifier.shorten(10)} (#{req.current_absolute_uri})"

      error_response "Cripes! You have been rate limited."

    rescue Familia::NotConnected, Familia::Problem => ex
      OT.le "#{ex.class}: #{ex.message}"
      OT.le ex.backtrace
      error_response "An error occurred :["

    rescue Errno::ECONNREFUSED => ex
      OT.le ex.message
      OT.le ex.backtrace
      error_response "We'll be back shortly!"

    rescue StandardError => ex
      custid = cust&.custid || '<notset>'
      sessid = sess&.short_identifier || '<notset>'
      OT.le "#{ex.class}: #{ex.message} -- #{req.current_absolute_uri} -- #{req.client_ipaddress} #{custid} #{sessid} #{locale} #{content_type} #{redirect} "
      OT.le ex.backtrace.join("\n")

      error_response "An unexpected error occurred :["

    ensure
      @sess ||= OT::Session.new 'failover', 'anon'
      @cust ||= OT::Customer.anonymous
    end

    # Find the locale of the request based on req.env['rack.locale']
    # which is set automatically by Otto.
    # If `locale` is specifies it will override if available.
    # If the `local` query param is set, it will override.
    def check_locale! locale=nil
      OT.ld "Starting check_locale! with initial locale: #{locale}"

      locales = req.env['rack.locale'] || []
      OT.ld "Initial locales from rack.locale: #{locales}"

      if locale.is_a?(String)
        locales.unshift locale.split('-').first
        OT.ld "Added locale prefix to locales: #{locales}"
      end

      locales << OT.conf[:locales].first
      OT.ld "Added first configured locale: #{locales}"

      locales.uniq!
      OT.ld "After removing duplicates: #{locales}"

      locales = locales.reject { |l| !OT.locales.has_key?(l) }.compact
      OT.ld "After filtering unavailable locales: #{locales}"

      if !OT.locales.has_key?(locale)
        locale = locales.first
        OT.ld "Defaulting to first available locale: #{locale}"
      end

      req.env['ots.locale'], req.env['ots.locales'] = (@locale = locale), locales
      OT.ld "Final locale: #{@locale}, Final locales: #{locales}"
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
        ex = OT::BadShrimp.new(req.path, cust.custid, attempted_shrimp, shrimp)
        OT.ld "BAD SHRIMP for #{cust.custid}@#{req.path}: #{log_value}"
        sess.replace_shrimp! if replace && !shrimp_is_empty
        raise ex
      end
    end
    protected :validate_shrimp

    def check_session!
      return if @check_session_ran
      @check_session_ran = true

      # Load from redis or create the session
      if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
        @sess = OT::Session.load req.cookie(:sess)
      else
        @sess = OT::Session.create req.client_ipaddress, "anon", req.user_agent
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

      # Update the session fields in redis (including updated timestamp)
      sess.save

      # Only set the cookie after session is for sure saved to redis
      is_secure = Onetime.conf[:site][:ssl]

      # Update the session cookie
      res.send_cookie :sess, sess.sessid, sess.ttl, is_secure

      # Re-hydrate the customer object
      @cust = sess.load_customer || OT::Customer.anonymous

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
        OT.info "[sess.check_session] #{sess.short_identifier} #{custref} authenabled=#{authentication_enabled?.to_s}, sess=#{sess.authenticated?.to_s}"
      end

    end

    def authentication_enabled?
      # NOTE: Defaulting to disabled is the Right Thing to Do™. If the site
      #      configuration is missing, we should assume that authentication
      #      is disabled. This is a security feature. Even though it will be
      #      annoying for anyone upgrading to 0.15 that hasn't had a chance
      #      to update their existing configuration yet.
      authentication_enabled = OT.conf[:site][:authentication][:enabled] rescue false # rubocop:disable Style/RescueModifier
      signin_enabled = OT.conf[:site][:authentication][:signin] rescue false # rubocop:disable Style/RescueModifier

      # The only condition that allows a request to be authenticated is if
      # the site has authentication enabled, and the user is signed in. If a
      # user is signed in and the site configuration changes to disable it,
      # the user will be signed out temporarily. If the setting is restored
      # before the session key expires in Redis, that user will be signed in
      # again. This is a security feature.
      authentication_enabled && signin_enabled
    end

    def stringify_request_details(req)
      header_details = collect_proxy_header_details(req.env)

      details = [
        req.ip,
        "#{req.request_method} #{req.path_info}?#{req.query_string}",
        "Proxy[#{header_details}]"
      ]

      # Convert the details array to a string for logging
      details.join('; ')
    end


    # Collects and formats specific HTTP header details from the given
    # environment hash.
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
    #     "REMOTE_ADDR" => "192.0.2.1"
    #   }
    #   collect_proxy_header_details(env)
    #   # => "HTTP_FLY_REQUEST_ID= HTTP_VIA= HTTP_X_FORWARDED_PROTO=
    #   HTTP_X_FORWARDED_FOR=203.0.113.195 HTTP_X_FORWARDED_HOST=
    #   HTTP_X_FORWARDED_PORT= HTTP_X_SCHEME= HTTP_X_REAL_IP=
    #   REMOTE_ADDR=192.0.2.1"
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

    def secure_request?
      !local? || secure?
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
      res.header['Cache-Control'] = "no-store, no-cache, must-revalidate, max-age=0"
      res.header['Expires'] = "Mon, 7 Nov 2011 00:00:00 UTC"
      res.header['Pragma'] = "no-cache"
    end

    def app_path *paths
      paths = paths.flatten.compact
      paths.unshift req.script_name
      paths.join('/').gsub '//', '/'
    end

  end
end
