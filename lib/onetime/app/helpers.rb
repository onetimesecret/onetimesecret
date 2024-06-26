
class Onetime::App
  class Unauthorized < RuntimeError
  end
  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
  end
  unless defined?(Onetime::App::BADAGENTS)
    BADAGENTS = [:facebook, :google, :yahoo, :bing, :stella, :baidu, :bot, :curl, :wget]
    LOCAL_HOSTS = ['localhost', '127.0.0.1'].freeze  # TODO: Add config
  end

  module Helpers

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

    def carefully redirect=nil # rubocop:disable Metrics/MethodLength
      redirect ||= req.request_path

      # Determine the locale for the current request
      # We check get here to stop an infinite redirect loop.
      # Pages redirecting from a POST can get by with the same page once.
      redirect = '/error' if req.get? && redirect.to_s == req.request_path

      unless res.header['Content-Language']
        res.header['Content-Language'] = req.env['ots.locale'] || req.env['rack.locale'] || OT.conf[:locales].first
      end

      res.header['Content-Type'] ||= "text/html; charset=utf-8"
      yield

    rescue Redirect => ex
      OT.ld "[carefully] Redirecting to #{ex.location} (#{ex.status})"
      res.redirect ex.location, ex.status

    rescue OT::App::Unauthorized => ex
      OT.info ex.message
      not_found_response "Not authorized"

    rescue OT::BadShrimp => ex
      sess.set_error_message "Please go back, refresh the page, and try again."
      res.redirect redirect

    rescue OT::FormError => ex
      handle_form_error ex, redirect

    rescue OT::MissingSecret => ex
      secret_not_found_response

    rescue OT::LimitExceeded => ex
      obscured = if cust.anonymous?
                   'anonymous'
                 else
                   OT::Utils.obscure_email(cust.custid)
                 end
      OT.le "[limit-exceeded] #{obscured} (#{sess.ipaddress}): #{ex.event}(#{ex.count}) #{sess.identifier.shorten(10)} (#{req.current_absolute_uri})"

      error_response "Cripes! You have been rate limited."

    rescue Familia::NotConnected, Familia::Problem => ex
      err "#{ex.class}: #{ex.message}"
      err ex.backtrace
      error_response "An error occurred :["

    rescue Errno::ECONNREFUSED => ex
      OT.info ex.message
      OT.le ex.backtrace
      error_response "We'll be back shortly!"

    rescue StandardError => ex
      err "#{ex.class}: #{ex.message}"
      err req.current_absolute_uri
      err ex.backtrace.join("\n")
      error_response "An unexpected error occurred :["

    ensure
      @sess ||= OT::Session.new :failover
      @cust ||= OT::Customer.anonymous
    end

    # Find the locale of the request based on req.env['rack.locale']
    # which is set automatically by Otto v0.4.0 and greater.
    # If `locale` is specifies it will override if available.
    # If the `local` query param is set, it will override.
    def check_locale! locale=nil
      locale = locale || req.cookie(:locale) if req.cookie?(:locale) # Use cookie value
      unless req.params[:locale].to_s.empty?
        locale = req.params[:locale]                                 # Use query param
        res.send_cookie :locale, locale, 4.hours, Onetime.conf[:site][:ssl]
      end
      locales = req.env['rack.locale'] || []                          # Requested list
      locales.unshift locale.split('-').first if locale.is_a?(String) # Support both en and en-US
      locales << OT.conf[:locales].first                              # Ensure at least one configured locale is available
      locales.uniq!
      locales = locales.reject { |l| !OT.locales.has_key?(l) }.compact
      locale = locales.first if !OT.locales.has_key?(locale)           # Default to the first available
      req.env['ots.locale'], req.env['ots.locales'] = (@locale = locale), locales
    end

    # Check XSRF value submitted with POST requests (aka shrimp)
    def check_shrimp!
      return if @check_shrimp_ran
      @check_shrimp_ran = true
      return unless req.post? || req.put? || req.delete?
      attempted_shrimp = req.params[:shrimp]

      ### NOTE: MUST FAIL WHEN NO SHRIMP OTHERWISE YOU CAN
      ### JUST SUBMIT A FORM WITHOUT ANY SHRIMP WHATSOEVER.
      unless sess.shrimp?(attempted_shrimp) || ignoreshrimp
        shrimp = (sess.shrimp || '[noshrimp]').clone
        sess.clear_shrimp!  # assume the shrimp is being tampered with
        ex = OT::BadShrimp.new(req.path, cust.custid, attempted_shrimp, shrimp)
        OT.ld "BAD SHRIMP for #{cust.custid}@#{req.path}: #{attempted_shrimp}"
        raise ex
      end
    end

    def check_session!
      return if @check_session_ran
      @check_session_ran = true

      # Load from redis or create the session
      if req.cookie?(:sess) && OT::Session.exists?(req.cookie(:sess))
        @sess = OT::Session.load req.cookie(:sess)
      else
        @sess = OT::Session.create req.client_ipaddress, "anon", req.user_agent
      end

      # Immediately check the the auth status of the session. If the site
      # configuration changes to disable authentication, the session will
      # report as not authenticated regardless of the session data.
      #
      # NOTE: The session keys have their own dedicated Redis DB, so they
      # can be flushed to force everyone to logout without affecting the
      # rest of the data. This is a security feature.
      sess.disable_auth = !authentication_enabled?

      # Update the session fields in redis
      sess.update_fields  # calls update_time!

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
      elsif cust.verified.to_s != 'true' && !sess['authenticated_by']
        sess.authenticated = false
      end

      custref = cust.obscure_email

      # Should always report false and false when disabled.
      templ = '[sess.check_session] %s %s authenabled=%s, sess=%s'
      margs = [sess.short_identifier, custref, authentication_enabled?, sess.authenticated?]
      OT.info format(templ, *margs)

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

    def secure_request?
      !local? || secure?
    end

    def secure?
      # X-Scheme is set by nginx
      # X-FORWARDED-PROTO is set by elastic load balancer
      (req.env['HTTP_X_FORWARDED_PROTO'] == 'https' || req.env['HTTP_X_SCHEME'] == "https")
    end

    def local?
      (LOCAL_HOSTS.member?(req.env['SERVER_NAME']) && (req.client_ipaddress == '127.0.0.1'))
    end

    def err *args
      prefix = "D(#{Time.now.to_i}):  "
      msg = "#{prefix}" << args.join() # msg.join("#{$/}#{prefix}")
      SYSLOG.err msg
      STDERR.puts msg
    end

    def deny_agents! *agents
      BADAGENTS.flatten.each do |agent|
        if req.user_agent =~ /#{agent}/i
          raise Redirect.new('/')
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
