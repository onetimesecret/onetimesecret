# apps/web/auth/config/hooks/session_integration.rb

module Auth::Config::Hooks::SessionIntegration
  # Pure business logic handlers - no error handling
  module Handlers
    # Syncs Rodauth session with application session format after successful login
    #
    # @param account [Hash] Rodauth account hash
    # @param account_id [Integer] Rodauth account ID
    # @param session [Hash] Rack session
    # @param request [Rack::Request] Request object
    def self.sync_session_after_login(account, account_id, session, request)
      OT.info "[session-integration] ===== AFTER_LOGIN HOOK CALLED ====="

      # Clear rate limiting on successful login
      rate_limit_key = "login_attempts:#{account[:email]}"
      client = Familia.dbclient
      client.del(rate_limit_key)

      # Load customer for session sync
      customer = if account[:external_id]
        Onetime::Customer.find_by_extid(account[:external_id])
      else
        Onetime::Customer.load(account[:email])
      end

      # Sync Rodauth session with application session format
      # Now that we're using :rack_session plugin, Rodauth's session
      # accessor points directly to Rack's env['rack.session']
      OT.info "[session-integration] BEFORE WRITE - Session class: #{session.class}"
      OT.info "[session-integration] BEFORE WRITE - Session ID: #{session.id.public_id rescue session.id rescue 'no-id'}"

      session['authenticated'] = true
      session['authenticated_at'] = Familia.now.to_i
      session['advanced_account_id'] = account_id
      session['account_external_id'] = account[:external_id]

      if customer
        session['identity_id'] = customer.custid
        session['email'] = customer.email
        session['locale'] = customer.locale || 'en'
      else
        session['email'] = account[:email]
      end

      # Track metadata
      session['ip_address'] = request.ip
      session['user_agent'] = request.user_agent

      OT.info "[session-integration] AFTER WRITE - Session synced for #{session['email']}"
      OT.info "[session-integration] AFTER WRITE - authenticated=#{session['authenticated']}, identity_id=#{session['identity_id']}"
      OT.info "[session-integration] AFTER WRITE - Session ID: #{session.id.public_id rescue session.id rescue 'no-id'}"
      OT.info "[session-integration] AFTER WRITE - Session keys: #{session.keys.join(', ') rescue 'error'}"
    end
  end

  def self.configure
    proc do
      # Clear rate limit and sync application session on successful login
      after_login do
        OT.info "[auth] User logged in: #{account[:email]}"

        Onetime::ErrorHandler.safe_execute('sync_session_after_login',
          account_id: account_id,
          email: account[:email]) do
          Handlers.sync_session_after_login(account, account_id, session, request)
        end
      end

      before_logout do
        OT.info "[auth] User logging out: #{session['email'] || 'unknown'}"
      end

      after_logout do
        OT.info "[auth] Logout complete"
      end
    end
  end
end
