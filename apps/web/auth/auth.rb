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

    # Handle empty path (when accessed as /auth without trailing slash)
    if r.path_info == ""
      { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
    end

    # Home page - JSON API info
    r.root do
      { message: 'OneTimeSecret Authentication Service API', endpoints: %w[/health /validate /account] }
    end

    # Use modular route handlers
    handle_health_routes(r)
    handle_validation_routes(r)
    handle_account_routes(r)
    handle_admin_routes(r)

    # All Rodauth routes (login, logout, create-account, etc.)
    r.rodauth

    # Catch-all for undefined routes
    response.status = 404
    { error: 'Endpoint not found' }
  end
end
