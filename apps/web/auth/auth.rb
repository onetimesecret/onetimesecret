#!/usr/bin/env ruby

require 'bundler/setup'
require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

# Database connection
database_url = ENV['DATABASE_URL'] || 'sqlite://auth.db'
DB = Sequel.connect(database_url)

# Enable SQL logging in development
if ENV['RACK_ENV'] == 'development'
  DB.loggers << Logger.new($stdout)
end

class AuthService < Roda
  # Roda plugins
  plugin :sessions, secret: ENV['AUTH_SECRET'] || 'dev-secret-change-in-production-this-must-be-at-least-64-chars-long'
  plugin :flash
  plugin :json
  plugin :halt
  plugin :error_handler
  plugin :status_handler
  plugin :render, views: File.expand_path('views', __dir__), layout: 'layout'
  plugin :assets, css: 'app.css', js: 'app.js', path: File.expand_path('assets', __dir__)

  # Status handlers
  status_handler(404) do
    { error: 'Not found' }
  end

  # Rodauth plugin configuration
  plugin :rodauth do
    db DB

    # HMAC secret for token security
    hmac_secret ENV['HMAC_SECRET'] || ENV['AUTH_SECRET'] || 'dev-hmac-secret-change-in-production'

    prefix '/auth'

    # Enable base feature for HTML rendering
    enable :base

    # JSON feature
    enable :json

    # Core authentication features
    enable :login, :logout, :create_account, :close_account, :login_password_requirements_base
    enable :change_password, :reset_password
    enable :remember  # "Remember me" functionality
    enable :verify_account  # Disabled until email is properly configured

    # JSON response configuration
    json_response_success_key :success
    json_response_error_key :error

    # Template configuration (after enabling features)
    # login_view { 'login' }
    # create_account_view 'create-account'
    # reset_password_request_view { 'reset-password-request' }
    # reset_password_view { 'reset-password' }


    # Use email as the account identifier
    account_id_column :id
    login_column :email
    login_label 'Email'
    require_login_confirmation? false
    require_password_confirmation? false

    # Security features
    enable :lockout   # Brute force protection
    enable :active_sessions  # Track active sessions

    # Session configuration
    session_key '_auth_session'
    remember_cookie_key '_auth_remember'

    # Account verification (email confirmation) - disabled
    # require_email_confirmation_for_new_accounts true
    # verify_account_email_subject 'OneTimeSecret - Confirm Your Account'

    # Password requirements
    password_minimum_length 8
    # password_complexity_requirements_enforced true

    # Lockout settings (brute force protection)
    max_invalid_logins 5
    # lockout_expiration_default 3600  # 1 hour

    # Email configuration
    send_email do |email|
      if ENV['RACK_ENV'] == 'production'
        # Use your email delivery service here
        # Example: SendGrid, SES, etc.
        deliver_email_via_service(email)
      else
        # Development: just log emails
        puts "\n=== EMAIL DEBUG ==="
        puts "To: #{email[:to]}"
        puts "Subject: #{email[:subject]}"
        puts "Body:\n#{email[:body]}"
        puts "=== END EMAIL ===\n"
      end
    end

    # Custom account creation logic
    after_create_account do
      puts "New account created: #{account[:email]} (ID: #{account_id})"

      # Add any custom logic here, such as:
      # - Creating default user preferences
      # - Sending welcome emails
      # - Setting up default roles
    end

    # Custom login logic
    after_login do
      puts "User logged in: #{account[:email]} from #{request.ip}"

      # Track login analytics or update last login time
      DB[:accounts].where(id: account_id).update(
        last_login_at: Sequel::CURRENT_TIMESTAMP,
        last_login_ip: request.ip
      )
    end

    # Handle login failures
    after_login_failure do
      puts "Login failure for: #{param('email')} from #{request.ip}"
    end
  end

  route do |r|
    # Debug logging
    puts "[#{Time.now}] #{r.request_method} #{r.path_info}" if ENV['RACK_ENV'] == 'development'

    # Serve assets
    r.assets

    # Home page - redirect to login if not logged in, account if logged in
    r.root do
      if rodauth.logged_in?
        r.redirect '/account'
      else
        r.redirect '/login'
      end
    end

    # Health check endpoint
    r.get 'health' do
      begin
        # Test database connection
        db_status = DB.test_connection ? 'ok' : 'error'

        {
          status: 'ok',
          timestamp: Time.now.utc.iso8601,
          database: db_status,
          version: '1.0.0'
        }
      rescue => e
        response.status = 503
        {
          status: 'error',
          error: e.message,
          timestamp: Time.now.utc.iso8601
        }
      end
    end

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

    # Account info endpoint
    r.get 'account' do
      begin
        unless rodauth.logged_in?
          if r.accept_json?
            response.status = 401
            next { error: 'Authentication required' }
          else
            flash[:error] = 'Please sign in to view your account.'
            r.redirect '/login'
          end
        end

        account = rodauth.account

        if r.accept_json?
          {
            id: account[:id],
            email: account[:email],
            created_at: account[:created_at],
            status: account[:status_id],
            email_verified: account[:status_id] == 2  # Assuming 2 is verified
          }
        else
          view 'account'
        end
      rescue => e
        puts "Error: #{e.class} - #{e.message}"
        puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

        if r.accept_json?
          response.status = 500
          { error: 'Internal server error' }
        else
          flash[:error] = 'An error occurred while loading your account.'
          r.redirect '/'
        end
      end
    end

    # Administrative endpoints (if needed)
    r.on 'admin' do
      # Add admin authentication here

      r.get 'stats' do
        begin
          {
            total_accounts: DB[:accounts].count,
            verified_accounts: DB[:accounts].where(status_id: 2).count,
            active_sessions: DB[:account_active_session_keys].count
          }
        rescue => e
          puts "Error: #{e.class} - #{e.message}"
          puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

          response.status = 500
          { error: 'Internal server error' }
        end
      end
    end

    # All Rodauth routes (login, logout, create-account, etc.)
    r.rodauth

    # Catch-all for undefined routes
    response.status = 404
    { error: 'Endpoint not found' }
  end

  private

  def validate_session_token(token)
    # This method would validate the session token
    # Implementation depends on how sessions are stored

    # Example for database-stored sessions:
    session_data = DB[:account_active_session_keys]
      .join(:accounts, id: :account_id)
      .where(session_id: token)
      .select(
        :account_id,
        :accounts__email,
        :accounts__created_at,
        :created_at___session_created_at,
        :last_use
      )
      .first

    return nil unless session_data

    # Check if session is still valid (not expired)
    session_expiry = session_data[:last_use] + (30 * 24 * 60 * 60)  # 30 days
    return nil if Time.now > session_expiry

    {
      account_id: session_data[:account_id],
      email: session_data[:email],
      created_at: session_data[:created_at],
      expires_at: session_expiry,
      roles: [],  # Could fetch from separate roles table
      features: ['secrets', 'create_secret', 'view_secret']
    }
  end

  def deliver_email_via_service(email)
    # Example implementation for production email delivery
    # You would replace this with your preferred email service

    case ENV['EMAIL_SERVICE']
    when 'sendgrid'
      deliver_via_sendgrid(email)
    when 'ses'
      deliver_via_ses(email)
    when 'smtp'
      deliver_via_smtp(email)
    else
      # Default: log to file in production
      File.open('log/emails.log', 'a') do |f|
        f.puts "#{Time.now.utc.iso8601}: #{email.inspect}"
      end
    end
  end
end
