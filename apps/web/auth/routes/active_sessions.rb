# apps/web/auth/routes/active_sessions.rb
#
# frozen_string_literal: true

require 'onetime/models/session_metadata'
require 'onetime/operations/sessions/list_for_customer'

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
            account_id         = rodauth.session_value
            current_session_id = rodauth.session[rodauth.session_id_session_key]

            # When the session_inactivity_deadline option is set it tells rodauth to:
            #   1. Update the last_use timestamp on every request where currently_active_session? is checked
            #   2. Automatically remove inactive sessions after N hours of inactivity
            #   3. Enforce a maximum session lifetime of M days
            rodauth.currently_active_session?

            # Verify account_id exists
            unless account_id
              response.status = 401
              next { error: 'Invalid session' }
            end

            # HMAC the current session ID for comparison with database values
            # (database stores HMAC-hashed session IDs for security)
            current_session_id_hmac = current_session_id ? rodauth.compute_hmac(current_session_id) : nil

            # Rodauth rows stay authoritative for session MEMBERSHIP and own the
            # revocation semantics (remove_active_session, the inactivity/lifetime
            # deadlines); the privacy-filtered SessionMetadata sidecar supplies the
            # display data. The two are joined on the sidecar's stored
            # active_session_id_hmac, which is the very value Rodauth persists in
            # its session_id column. Rodauth's token is its own minted
            # active_session_id, NOT the Rack sid, so no digest computed here from
            # a sid could ever match a row.
            sessions       = rodauth.db[:account_active_session_keys]
              .where(account_id: account_id)
              .order(Sequel.desc(:last_use))
              .all
            metadata_by_id = active_session_metadata_by_hmac(account_id)

            # Transform to frontend schema. A Rodauth row with no matching sidecar
            # (a session older than the sidecar, or older than the join key) falls
            # back to Rodauth's own timestamps and exposes no browser/network
            # details, because none were ever stored for it.
            sessions_data = sessions.map do |session|
              metadata = metadata_by_id[session[:session_id]]
              {
                id: session[:session_id],
                created_at: epoch_iso8601(metadata&.dig(:created_at)) || session[:created_at]&.iso8601,
                last_activity_at: epoch_iso8601(metadata&.dig(:last_activity_at)) || session[:last_use]&.iso8601,
                ip_address: metadata&.dig(:ip_address),
                user_agent: metadata&.dig(:user_agent),
                geo_country: metadata&.dig(:geo_country),
                is_current: session[:session_id] == current_session_id_hmac,
                remember_enabled: false,  # TODO: Check remember table if feature enabled
              }
            end

            response.headers['Content-Type'] = 'application/json'
            { sessions: sessions_data }
          rescue StandardError => ex
            auth_logger.error 'Error fetching active sessions',
              {
                exception: ex,
                account_id: account_id,
              }

            response.status = 500
            { error: 'Failed to fetch active sessions' }
          end

          # DELETE /auth/active-sessions/:session_id
          # Remove a specific active session
          r.is String do |session_id|
            next unless r.delete?

            current_session_id      = rodauth.session[rodauth.session_id_session_key]
            current_session_id_hmac = current_session_id ? rodauth.compute_hmac(current_session_id) : nil

            # Prevent removing current session via this endpoint
            if session_id == current_session_id_hmac
              response.status = 400
              next { error: 'Cannot remove current session. Use logout instead.' }
            end

            # Remove the session (session_id is already HMAC-hashed from database)
            rodauth.remove_active_session(session_id)

            response.headers['Content-Type'] = 'application/json'
            { success: 'Session removed successfully' }
          rescue StandardError => ex
            auth_logger.error 'Error removing active session',
              {
                exception: ex,
                session_id: session_id,
              }

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
          account_id = begin
                         rodauth.session_value
          rescue StandardError
                         nil
          end
          auth_logger.error 'Error removing all active sessions',
            {
              exception: ex,
              account_id: account_id,
            }

          response.status = 500
          { error: 'Failed to remove sessions' }
        end
      end

      private

      # Map HMAC(active_session_id) -> safe_dump metadata row, i.e. keyed by the
      # exact value the Rodauth session_id column holds. The operation returns each
      # row's internal join key alongside its safe display row, avoiding a second
      # SessionMetadata load per row.
      def active_session_metadata_by_hmac(account_id)
        active_session_metadata(account_id).entries.each_with_object({}) do |entry, map|
          hmac = entry.active_session_id_hmac
          next if hmac.to_s.empty?

          map[hmac] = entry.session
        end
      end

      def active_session_metadata(account_id)
        account = rodauth.db[:accounts].where(id: account_id).first
        return empty_active_session_metadata unless account

        customer = Onetime::Customer.find_by_extid(account[:external_id]) ||
                   Onetime::Customer.find_by_email(account[:email])
        return empty_active_session_metadata unless customer

        Onetime::Operations::Sessions::ListForCustomer.new(custid: customer.extid).call
      end

      def empty_active_session_metadata
        Onetime::Operations::Sessions::ListForCustomer::Result.new(entries: [])
      end

      def epoch_iso8601(epoch)
        return nil if epoch.nil?

        Time.at(epoch.to_i).utc.iso8601
      end
    end
  end
end
