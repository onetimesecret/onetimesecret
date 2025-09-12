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
      otto.add_auth_strategy('v2_basic', V2BasicStrategy.new)

      # Session-based authentication
      otto.add_auth_strategy('v2_session', V2SessionStrategy.new)

      # Combined basic + session authentication (most V2 endpoints)
      otto.add_auth_strategy('v2_api', V2CombinedStrategy.new)

      # Optional authentication (allows anonymous)
      otto.add_auth_strategy('v2_optional', V2OptionalStrategy.new)

      # Colonel/admin authentication
      otto.add_auth_strategy('v2_colonel', V2ColonelStrategy.new)
    end

    # Basic authentication with API token
    class V2BasicStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        auth = Rack::Auth::Basic::Request.new(env)

        if auth.provided? && auth.basic?
          custid, apitoken = auth.credentials
          return failure('Invalid credentials format') if custid.to_s.empty? || apitoken.to_s.empty?

          OT.ld "[v2_basic] Attempt for '#{custid}' via #{env['REMOTE_ADDR']}"
          cust = V2::Customer.load(custid)
          return failure('Customer not found') if cust.nil?

          if cust.apitoken?(apitoken)
            OT.ld "[v2_basic] Authenticated '#{custid}'"
            return success({
              session: env['onetime.session'] || {},
              user: cust,
              auth_method: 'basic'
            })
          end
        end

        failure('Invalid API credentials')
      end
    end

    # Session-based authentication
    class V2SessionStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        session = env['onetime.session']

        if session && session['identity_id']
          cust = V2::Customer.load(session['identity_id'])

          if cust
            OT.ld "[v2_session] Authenticated '#{cust.custid}' via session"
            return success({
              session: session,
              user: cust,
              auth_method: 'session'
            })
          end
        end

        failure('Invalid session')
      end
    end

    # Combined basic + session authentication
    class V2CombinedStrategy < Otto::Security::AuthStrategy
      def authenticate(env, requirement)
        # Try basic auth first
        basic_strategy = V2BasicStrategy.new
        if result = basic_strategy.authenticate(env, requirement)
          return result if result.success?
        end

        # Fall back to session auth
        session_strategy = V2SessionStrategy.new
        if result = session_strategy.authenticate(env, requirement)
          return result if result.success?
        end

        failure('No valid authentication found')
      end
    end

    # Optional authentication (allows anonymous)
    class V2OptionalStrategy < Otto::Security::AuthStrategy
      def authenticate(env, requirement)
        # Try authenticated methods first
        combined_strategy = V2CombinedStrategy.new
        if result = combined_strategy.authenticate(env, requirement)
          return result if result.success?
        end

        # Allow anonymous access
        session = env['onetime.session']
        cust = V2::Customer.anonymous

        OT.ld "[v2_optional] Anonymous access via #{env['REMOTE_ADDR']}"

        success({
          session: session || {},
          user: cust,
          auth_method: 'anonymous'
        })
      end
    end

    # Colonel/admin authentication
    class V2ColonelStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        # Require session authentication for colonel access
        session = env['onetime.session']

        if session && session['identity_id']
          cust = V2::Customer.load(session['identity_id'])

          # Check if customer has colonel privileges
          if cust && cust.colonel?
            OT.ld "[v2_colonel] Colonel authenticated '#{cust.custid}'"
            return success({
              session: session,
              user: cust,
              auth_method: 'colonel'
            })
          end
        end

        OT.ld "[v2_colonel] Access denied - colonel privileges required"
        failure('Colonel privileges required')
      end
    end
  end
end
