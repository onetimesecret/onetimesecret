# lib/auth_integration.rb

require 'net/http'
require 'json'

module AuthIntegration
  class SessionValidator
    AUTH_SERVICE_URL = ENV['AUTH_SERVICE_URL'] || 'http://localhost:7143'

    def self.validate_session(session_token)
      return nil unless session_token

      begin
        uri = URI("#{AUTH_SERVICE_URL}/validate")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = { token: session_token }.to_json

        response = http.request(request)

        if response.code == '200'
          result = JSON.parse(response.body)
          return result if result['valid']
        end

        nil
      rescue StandardError => e
        # Log error in production, but don't expose details
        puts "Auth validation error: #{e.message}" if ENV['RACK_ENV'] == 'development'
        nil
      end
    end

    def self.get_user_from_session(session_token)
      validation = validate_session(session_token)
      validation&.dig('user_data')
    end
  end

  # Middleware to add authentication context to requests
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Extract session token from cookie
      session_token = extract_session_token(request)

      if session_token
        user_data = SessionValidator.get_user_from_session(session_token)
        env['auth.user'] = user_data if user_data
        env['auth.authenticated'] = !user_data.nil?
      else
        env['auth.authenticated'] = false
      end

      @app.call(env)
    end

    private

    def extract_session_token(request)
      # Try multiple cookie names that might contain the session
      cookie_names = ['onetime.session', '_auth_shrimp', 'rack.session']

      cookie_names.each do |name|
        value = request.cookies[name]
        return value if value && !value.empty?
      end

      nil
    end
  end

  # Helper methods for controllers
  module ControllerHelpers
    def authenticated?
      env['auth.authenticated'] == true
    end

    def current_user
      env['auth.user']
    end

    def require_authentication!
      unless authenticated?
        redirect_to_auth
      end
    end

    def redirect_to_auth
      auth_url = ENV['AUTH_SERVICE_URL'] || 'http://localhost:7143'
      redirect_url = "#{auth_url}/auth/login"

      # Store return URL for post-login redirect
      session[:return_to] = request.url if session

      response.redirect(redirect_url)
    end
  end
end
