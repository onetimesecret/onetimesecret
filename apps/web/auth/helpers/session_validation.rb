# apps/web/auth/helpers/session_validation.rb

module Auth
  module Helpers
    module SessionValidation
      def validate_session_token(token)
        # This method would validate the session token
        # Implementation depends on how sessions are stored

        # Example for database-stored sessions:
        db           = Auth::Config::Database.connection
        session_data = db[:account_active_session_keys]
          .join(:accounts, id: :account_id)
          .where(session_id: token)
          .select(
            :account_id,
            :accounts__email,
            :accounts__created_at,
            :created_at___session_created_at,
            :last_use,
          )
          .first

        return nil unless session_data

        # Check if session is still valid (not expired)
        session_expiry = session_data[:last_use] + (30 * 24 * 60 * 60)  # 30 days
        return nil if Time.now > session_expiry

        # Check if MFA is enabled for this account
        mfa_enabled = db[:account_otp_keys].where(id: session_data[:account_id]).count > 0

        {
          account_id: session_data[:account_id],
          email: session_data[:email],
          created_at: session_data[:created_at],
          expires_at: session_expiry,
          mfa_enabled: mfa_enabled,
          roles: [],  # Could fetch from separate roles table
          features: %w[secrets create_secret view_secret],
        }
      end
    end
  end
end
