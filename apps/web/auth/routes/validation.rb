# apps/web/auth/routes/validation.rb

module Auth
  module Routes
    module Validation
      def handle_validation_routes(r)
        # Token validation endpoint for main OneTimeSecret app
        r.on 'validate' do
          r.post do
            handle_token_validation(r)
          end

          r.get do
            handle_session_validation(r)
          end
        end
      end

      private

      def handle_token_validation(r)
          # Original token-based validation logic

          token = r.params['token'] || r.params['session_id']

          unless token
            response.status = 400
            return { error: 'Token required' }
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
                features: session_info[:features] || [],
              },
              expires_at: session_info[:expires_at],
            }
          else
            response.status = 401
            {
              valid: false,
              error: 'Invalid or expired token',
            }
          end
      rescue Sequel::ValidationFailed => ex
          response.status = 400
          { error: 'Validation failed', details: ex.errors }
      rescue Sequel::UniqueConstraintViolation
          response.status = 409
          { error: 'Account already exists' }
      rescue StandardError => ex
          puts "Error: #{ex.class} - #{ex.message}"
          puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

          response.status = 500
          {
            valid: false,
            error: 'Token validation failed',
            details: ENV['RACK_ENV'] == 'development' ? ex.message : nil,
          }
      end

      def handle_session_validation(r)
          # Session-based validation for frontend auth checks
          # Works with both basic and advanced auth modes

          auth_mode = Onetime.auth_config.mode

          case auth_mode
          when 'advanced'
            validate_advanced_session(r)
          when 'basic'
            validate_basic_session(r)
          else
            response.status = 503
            { valid: false, error: "Unknown authentication mode: #{auth_mode}" }
          end
      rescue StandardError => ex
          puts "Error in session validation: #{ex.class} - #{ex.message}"
          puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

          response.status = 500
          {
            valid: false,
            error: 'Session validation failed',
            details: ENV['RACK_ENV'] == 'development' ? ex.message : nil,
          }
      end

      def validate_advanced_session(_r)
        # Use Rodauth for advanced mode
        if rodauth.logged_in?
          account = rodauth.account
          # Return format compatible with frontend checkAuth schema
          {
            success: true,
            record: {
              custid: account[:email],
              objid: account[:id].to_s,
              created: account[:created_at]&.to_i,
              updated: account[:updated_at]&.to_i,
              # Add other customer fields as needed
            },
            details: {
              authenticated: true,
            },
          }
        else
          response.status = 401
          {
            success: false,
            error: 'Not authenticated',
            record: nil,
            details: { authenticated: false },
          }
        end
      end

      def validate_basic_session(r)
        # Use Redis session for basic mode
        session = r.env['rack.session']

        if session && session['identity_id'] && session['authenticated']
          begin
            # Load customer from session
            require_relative '../../../lib/onetime' unless defined?(Onetime::Customer)
            customer = Onetime::Customer.load(session['identity_id'])

            if customer && !customer.anonymous?
              # Return format compatible with frontend checkAuth schema
              {
                success: true,
                record: customer.safe_dump,
                details: {
                  authenticated: true,
                },
              }
            else
              response.status = 401
              {
                success: false,
                error: 'Invalid session',
                record: nil,
                details: { authenticated: false },
              }
            end
          rescue StandardError => ex
            puts "Error loading customer: #{ex.message}" if ENV['RACK_ENV'] == 'development'
            response.status = 500
            {
              success: false,
              error: 'Session validation failed',
              record: nil,
              details: { authenticated: false },
            }
          end
        else
          response.status = 401
          {
            success: false,
            error: 'No valid session',
            record: nil,
            details: { authenticated: false },
          }
        end
      end
    end
  end
end
