# apps/api/v2/controllers/helpers.rb

require_relative '../../../../lib/onetime/helpers/session_helpers'
require_relative '../../../../lib/onetime/helpers/shrimp_helpers'

module V2
  unless defined?(V2::BADAGENTS)
    BADAGENTS     = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
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

      cust ||= Onetime::Customer.anonymous

      # Prevent infinite redirect loops by checking if the request is a GET request.
      # Pages redirecting from a POST request can use the same page once.
      redirect = '/500' if req.get? && redirect.to_s == req.request_path

      # Generate a unique nonce for this response
      nonce = SecureRandom.base64(16)

      # Make the nonce available to the CSP header
      add_csp_headers(content_type, nonce)

      # Make the nonce available to the view
      req.env['ots.nonce'] = nonce

      return_value = yield

      debug_log_request

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

      # Include fresh shrimp so they can try again, again 🦐
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
      # Fallback session no longer needed with Rack::Session
      @cust ||= Onetime::Customer.anonymous
    end

    # Sets the locale for the request based on various sources.
    #
    # This method uses Otto's generalized check_locale! helper to determine
    # the locale for the request. It passes the necessary Onetime Secret
    # configuration and stores the result in the expected instance variable.
    #
    # @param locale [String, nil] The locale to be used, if specified.
    # @return [void]
    def check_locale!(locale = nil)
      @locale = req.check_locale!(
        locale,
        {
          available_locales: OT.locales,
          default_locale: OT.default_locale,
          user_locale: cust&.locale,
          locale_env_key: 'ots.locale',
          debug: OT.debug?,
        },
      )
    end

    def add_csp_headers(content_type, nonce)
      # Skip the CSP header unless it's enabled in the experimental settings
      return unless OT.conf.dig('experimental', 'csp', 'enabled') == true

      # Use Otto's CSP nonce support
      res.send_csp_headers(
        content_type,
        nonce, {
          development_mode: OT.conf.dig('development', 'enabled'),
          debug: OT.debug?,
        }
      )
    end

    # Collects and formats specific HTTP header details from the given
    # environment hash, including Cloudflare-specific headers.
    #
    # @deprecated Use req.collect_proxy_headers instead
    # @param env [Hash, nil] The environment hash containing HTTP headers.
    #   Defaults to an empty hash if not provided.
    # @param keys [Array<String>, nil] The list of HTTP header keys to collect.
    #   Defaults to a predefined list of common proxy-related headers if not
    #   provided.
    # @return [String] A single string with the requested headers formatted as
    #   "key=value" pairs, separated by spaces.
    #
    def collect_proxy_header_details(env = nil, keys = nil)
      # For backward compatibility, create a simple request-like object
      request_like = Struct.new(:env).new(env || req.env)
      request_like.extend(Otto::RequestHelpers)

      additional_keys = keys || []
      request_like.collect_proxy_headers(
        header_prefix: HEADER_PREFIX.chomp('_'),
        additional_keys: additional_keys,
      )
    end

    def setup_request_context
      return if @request_context_setup

      @request_context_setup = true

      # Session is already loaded by Onetime::Session middleware
      # No need to manually load or create sessions

      # Load customer based on session state
      @cust = current_customer

      # Track request for security monitoring
      if authenticated?
        custref = @cust.obscure_email
        OT.ld "[session.request] #{custref} #{request.request_method} #{request.path}"
      end
    end

    # Check CSRF value submitted with POST requests (aka shrimp)
    def check_shrimp!
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

    def debug_log_request
      # Use Otto's format_request_details method with our custom header prefix
      reqstr  = req.format_request_details(header_prefix: HEADER_PREFIX)
      custref = cust.obscure_email

      session_id = session.id&.to_s || req.cookies['onetime.session'] || 'unknown'
      short_session_id = session_id.length <= 10 ? session_id : session_id[0, 10] + '...'
      OT.ld "[carefully] #{short_session_id} #{custref} at #{reqstr}"
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
