# frozen_string_literal: true

module Auth
  module Routes
    module Validation
      def handle_validation_routes(r)
        # Token validation endpoint for main OneTimeSecret app
        r.post 'validate' do
          begin
            token = r.params['token'] || r.params['session_id']

            unless token
              response.status = 400
              next { error: 'Token required' }
            end

            # Check if token corresponds to valid session
            session_info = validate_session_token(token)

            if session_info
              {
                valid: true,
                user_data: {
                  id: session_info[:account_id],
                  email: session_info[:email],
                  created_at: session_info[:created_at],
                  roles: session_info[:roles] || [],
                  features: session_info[:features] || []
                },
                expires_at: session_info[:expires_at]
              }
            else
              response.status = 401
              {
                valid: false,
                error: 'Invalid or expired token'
              }
            end
          rescue Sequel::ValidationFailed => e
            response.status = 400
            { error: 'Validation failed', details: e.errors }
          rescue Sequel::UniqueConstraintViolation => e
            response.status = 409
            { error: 'Account already exists' }
          rescue => e
            puts "Error: #{e.class} - #{e.message}"
            puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            {
              valid: false,
              error: 'Token validation failed',
              details: ENV['RACK_ENV'] == 'development' ? e.message : nil
            }
          end
        end
      end
    end
  end
end
