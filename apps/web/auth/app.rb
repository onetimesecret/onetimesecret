#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'roda'
require 'rodauth'
require 'sequel'
require 'logger'
require 'json'

# Load modular configuration
require_relative 'config/database'
require_relative 'config/rodauth_main'
require_relative 'helpers/session_validation'
require_relative 'routes/health'
require_relative 'routes/validation'
require_relative 'routes/account'
require_relative 'routes/admin'

class AuthService < Roda
  # Include session validation helpers
  include Auth::Helpers::SessionValidation

  # Include route modules
  include Auth::Routes::Health
  include Auth::Routes::Validation
  include Auth::Routes::Account
  include Auth::Routes::Admin

  # Redis session middleware (unified with other apps)
  require 'onetime/session'
  use Onetime::Session, Auth::Config::Database.session_config

  plugin :json
  plugin :halt
  plugin :error_handler
  plugin :status_handler

  # Status handlers
  status_handler(404) do
    { error: 'Not found' }
  end

  # Rodauth plugin configuration
  plugin :rodauth, &Auth::Config::RodauthMain.configure

  route do |r|
    # Debug logging
    if ENV['RACK_ENV'] == 'development'
      puts "[#{Time.now}] #{r.request_method} #{r.path_info}"
      puts "  PATH_INFO: '#{r.env['PATH_INFO']}'"
      puts "  REQUEST_URI: '#{r.env['REQUEST_URI']}'"
      puts "  SCRIPT_NAME: '#{r.env['SCRIPT_NAME']}'"
    end

    # Determine auth mode at request time
    auth_mode = Onetime.auth_config.mode

    # Handle empty path (when accessed as /auth without trailing slash)
    if r.path_info == ""
      { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
    end

    # Home page - JSON API info
    r.root do
      { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
    end

    # Use modular route handlers (always available)
    handle_health_routes(r)
    handle_validation_routes(r)
    handle_account_routes(r)
    handle_admin_routes(r)

    # Handle auth mode routing
    case auth_mode
    when 'advanced'
      # Use full Rodauth functionality
      r.rodauth
    when 'basic'
      # Handle basic auth mode with core controller forwarding
      handle_basic_auth_routes(r)
    else
      response.status = 503
      { error: "Unknown authentication mode: #{auth_mode}" }
    end

    # Catch-all for undefined routes
    response.status = 404
    { error: 'Endpoint not found' }
  end

  private

  def handle_basic_auth_routes(r)
    # Handle login endpoint
    r.on('login') do
      forward_to_core_auth('/signin', r)
    end

    # Handle logout endpoint
    r.on('logout') do
      forward_to_core_auth('/logout', r)
    end

    # Handle account creation
    r.on('create-account') do
      forward_to_core_auth('/signup', r)
    end

    # Handle account info (already handled by handle_account_routes above)
    # The validate endpoint is already handled by handle_validation_routes

    # For any other routes, we don't handle them in basic mode
    nil
  end

  def forward_to_core_auth(path, r)
    # Create a new env with the mapped path for forwarding to core controllers
    new_env = r.env.dup
    new_env['PATH_INFO'] = path
    new_env['REQUEST_URI'] = new_env['REQUEST_URI'].sub(r.path_info, path)

    # Try to get the core web application
    core_app = get_core_web_app

    if core_app
      # Forward the request to the core app
      status, headers, body = core_app.call(new_env)

      # Set response
      response.status = status
      headers.each { |k, v| response.headers[k] = v unless k.downcase == 'content-length' }

      # Handle the response based on content type
      if headers['Content-Type']&.include?('application/json')
        # Parse JSON response
        body_str = body.is_a?(Array) ? body.join : body.to_s
        begin
          JSON.parse(body_str)
        rescue JSON::ParserError
          { error: 'Invalid JSON response from core auth' }
        end
      elsif status >= 300 && status < 400 && headers['Location']
        # Handle redirects - convert to JSON for API consistency
        if r.env['HTTP_ACCEPT']&.include?('application/json')
          { success: true, redirect: headers['Location'] }
        else
          response.redirect(headers['Location'])
          nil
        end
      else
        # For other content types, return as-is
        body.is_a?(Array) ? body.join : body.to_s
      end
    else
      response.status = 503
      { error: 'Core authentication service unavailable' }
    end
  end

  def get_core_web_app
    # Get the Core web application from the app registry
    if defined?(AppRegistry) && AppRegistry.respond_to?(:mount_mappings)
      core_app_class = AppRegistry.mount_mappings['/']
      core_app_class&.new
    end
  rescue StandardError => e
    puts "Error getting core app: #{e.message}" if ENV['RACK_ENV'] == 'development'
    nil
  end
end
