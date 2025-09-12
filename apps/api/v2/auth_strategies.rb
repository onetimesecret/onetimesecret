# apps/api/v2/auth_strategies.rb
#
# Otto authentication strategies for V2 API endpoints.
# These strategies handle the various authentication methods used by V2 controllers.

module V2
  module AuthStrategies
    extend self

    def register_all(otto)
      otto.enable_authentication!

      # Basic authentication with API token
      otto.add_auth_strategy('v2_basic', basic_auth_strategy)

      # Session-based authentication
      otto.add_auth_strategy('v2_session', session_auth_strategy)

      # Combined basic + session authentication (most V2 endpoints)
      otto.add_auth_strategy('v2_api', combined_auth_strategy)

      # Optional authentication (allows anonymous)
      otto.add_auth_strategy('v2_optional', optional_auth_strategy)

      # Colonel/admin authentication
      otto.add_auth_strategy('v2_colonel', colonel_auth_strategy)
    end

    private

    def basic_auth_strategy
      lambda do |req|
        auth = Rack::Auth::Basic::Request.new(req.env)

        if auth.provided? && auth.basic?
          custid, apitoken = auth.credentials
          return nil if custid.to_s.empty? || apitoken.to_s.empty?

          OT.ld "[v2_basic] Attempt for '#{custid}' via #{req.env['REMOTE_ADDR']}"
          cust = V2::Customer.load(custid)
          return nil if cust.nil?

          if cust.apitoken?(apitoken)
            OT.ld "[v2_basic] Authenticated '#{custid}'"
            return OpenStruct.new(
              session: req.env['onetime.session'],
              user: cust,
              auth_method: 'basic'
            )
          end
        end

        nil
      end
    end

    def session_auth_strategy
      lambda do |req|
        session = req.env['onetime.session']

        if session && session['identity_id']
          cust = V2::Customer.load(session['identity_id'])

          if cust
            OT.ld "[v2_session] Authenticated '#{cust.custid}' via session"
            return OpenStruct.new(
              session: session,
              user: cust,
              auth_method: 'session'
            )
          end
        end

        nil
      end
    end

    def combined_auth_strategy
      lambda do |req|
        # Try basic auth first
        if result = basic_auth_strategy.call(req)
          return result
        end

        # Fall back to session auth
        if result = session_auth_strategy.call(req)
          return result
        end

        nil
      end
    end

    def optional_auth_strategy
      lambda do |req|
        # Try authenticated methods first
        if result = combined_auth_strategy.call(req)
          return result
        end

        # Allow anonymous access
        session = req.env['onetime.session']
        cust = V2::Customer.anonymous

        OT.ld "[v2_optional] Anonymous access via #{req.env['REMOTE_ADDR']}"

        OpenStruct.new(
          session: session || {},
          user: cust,
          auth_method: 'anonymous'
        )
      end
    end

    def colonel_auth_strategy
      lambda do |req|
        # Require session authentication for colonel access
        session = req.env['onetime.session']

        if session && session['identity_id']
          cust = V2::Customer.load(session['identity_id'])

          # Check if customer has colonel privileges
          if cust && cust.colonel?
            OT.ld "[v2_colonel] Colonel authenticated '#{cust.custid}'"
            return OpenStruct.new(
              session: session,
              user: cust,
              auth_method: 'colonel'
            )
          end
        end

        OT.ld "[v2_colonel] Access denied - colonel privileges required"
        nil
      end
    end
  end
end
