# apps/web/auth/routes/active_sessions.rb

module Auth
  module Routes
    module ActiveSessions
      def handle_active_sessions_routes(r)
        r.on 'active-sessions' do
          # Require authentication for all session management endpoints
          unless rodauth.logged_in?
            response.status = 401
            next { error: 'Authentication required' }
          end

          # GET /auth/active-sessions
          # Returns list of all active sessions for the current user
          r.get do
            # Get account_id directly from session to avoid account lookup
            account_id = rodauth.session_value
            current_session_id = rodauth.active_sessions_key

            # Verify account_id exists
            unless account_id
              response.status = 401
              next { error: 'Invalid session' }
            end

            # Query active sessions from database
            sessions = rodauth.db[:account_active_session_keys]
              .where(account_id: account_id)
              .order(Sequel.desc(:last_use))
              .all

            # Transform to frontend schema
            sessions_data = sessions.map do |session|
              {
                id: session[:session_id],
                created_at: session[:created_at]&.iso8601,
                last_activity_at: session[:last_use]&.iso8601,
                ip_address: nil,  # TODO: Store IP in table if needed
                user_agent: nil,  # TODO: Store user agent if needed
                is_current: session[:session_id] == current_session_id,
                remember_enabled: false  # TODO: Check remember table if feature enabled
              }
            end

            response.headers['Content-Type'] = 'application/json'
            { sessions: sessions_data }
          rescue StandardError => ex
            auth_logger.error 'Error fetching active sessions',
              exception: ex,
              account_id: account_id

            response.status = 500
            { error: 'Failed to fetch active sessions' }
          end

          # DELETE /auth/active-sessions/:session_id
          # Remove a specific active session
          r.delete String do |session_id|
            current_session_id = rodauth.active_sessions_key

            # Prevent removing current session via this endpoint
            if session_id == current_session_id
              response.status = 400
              next { error: 'Cannot remove current session. Use logout instead.' }
            end

            # Remove the session
            rodauth.remove_active_session(session_id)

            response.headers['Content-Type'] = 'application/json'
            { success: 'Session removed successfully' }
          rescue StandardError => ex
            auth_logger.error 'Error removing active session',
              exception: ex,
              session_id: session_id

            response.status = 500
            { error: 'Failed to remove session' }
          end
        end

        # POST /auth/remove-all-active-sessions
        # Remove all sessions except the current one
        r.post 'remove-all-active-sessions' do
          unless rodauth.logged_in?
            response.status = 401
            next { error: 'Authentication required' }
          end

          # Remove all sessions except current
          rodauth.remove_all_active_sessions_except_current

          response.headers['Content-Type'] = 'application/json'
          { success: 'All other sessions have been removed' }
        rescue StandardError => ex
          # Use session_value for safer access to account_id
          account_id = rodauth.session_value rescue nil
          auth_logger.error 'Error removing all active sessions',
            exception: ex,
            account_id: account_id

          response.status = 500
          { error: 'Failed to remove sessions' }
        end
      end
    end
  end
end
