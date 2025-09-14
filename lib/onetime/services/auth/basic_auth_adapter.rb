# lib/onetime/services/auth/basic_auth_adapter.rb

require 'bcrypt'

module Auth
  class BasicAuthAdapter
    attr_reader :env

    def initialize(env)
      @env = env
    end

    def authenticate(email, password, tenant_id = nil)
      # Find the customer in Redis
      customer = find_customer(email, tenant_id)
      return authentication_failure unless customer

      # Verify password using bcrypt
      return authentication_failure unless verify_password(customer, password)

      # Create session via Rack::Session
      session                     = env['onetime.session']
      session['identity_id']      = customer.custid
      session['tenant_id']        = tenant_id || customer.custid
      session['email']            = customer.email
      session['authenticated']    = true
      session['authenticated_at'] = Time.now.to_i

      # Return success with customer data
      {
        success: true,
        identity_id: customer.custid,
        tenant_id: tenant_id || customer.custid,
        customer: customer,
      }
    rescue StandardError => ex
      OT.le "[BasicAuthAdapter] Authentication error: #{ex.message}"
      authentication_failure
    end

    def logout
      session = env['onetime.session']
      session.clear
      { success: true }
    end

    def current_identity
      session = env['onetime.session']
      return nil unless session['authenticated']

      {
        identity_id: session['identity_id'],
        tenant_id: session['tenant_id'],
        email: session['email'],
        authenticated_at: session['authenticated_at'],
      }
    end

    def authenticated?
      session = env['onetime.session']
      session['authenticated'] == true
    end

    private

    def find_customer(email, _tenant_id = nil)
      # Use the existing Customer model to load by email
      # In OTS, the custid IS the email address
      V2::Customer.load(email)
    end

    def verify_password(customer, password)
      # SECURITY: Timing attack mitigation - both code paths must execute identical operations
      # to prevent attackers from distinguishing valid vs invalid emails through timing analysis.
      # This ensures constant-time behavior regardless of customer existence.
      target_customer = if customer.has_passphrase?
        customer
      else
        V2::Customer.dummy
      end

      # Always perform passphrase verification and always return its result to mitigate timing attacks
      target_customer.passphrase?(password)
    rescue StandardError => ex
      OT.le "[BasicAuthAdapter] Password verification error: #{ex.message}"
      false
    end

    def authentication_failure
      {
        success: false,
        error: 'Invalid email or password',
      }
    end
  end
end
