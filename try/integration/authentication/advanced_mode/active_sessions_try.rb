# try/integration/authentication/advanced_mode/active_sessions_try.rb
#
# frozen_string_literal: true

# Integration tests for active sessions management in advanced mode
#
# Tests:
# - GET /auth/active-sessions - List all active sessions
# - DELETE /auth/active-sessions/:id - Remove specific session
# - POST /auth/remove-all-active-sessions - Remove all other sessions
# - Account info includes active_sessions_count
#
# REQUIRES: Advanced mode with SQL database

# Skip if not in advanced mode
require_relative '../../../support/test_helpers'
require_relative '../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :advanced

# Ensure database URL is configured
if ENV['DATABASE_URL'].to_s.strip.empty?
  puts "SKIPPING: Advanced mode requires DATABASE_URL."
  exit 0
end

# Setup
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/auth_config'
require 'onetime/middleware'
require 'onetime/application/registry'

Onetime::Application::Registry.prepare_application_registry

require 'rack/test'
require 'json'

# Create test instance
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def @test.json_response
  JSON.parse(last_response.body)
end

# Helper to create a test account
def @test.create_test_account(email = "sessions-test-#{Time.now.to_i}@example.com")
  response = post '/auth/create-account',
    { login: email, password: 'Test1234!@', 'password-confirm': 'Test1234!@' }.to_json,
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }

  # For verification, return the email
  email
end

# Helper to login
def @test.login(email, password = 'Test1234!@')
  post '/auth/login',
    { login: email, password: password }.to_json,
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }

  last_response.status == 200
end

# -------------------------------------------------------------------
# SETUP: Create test account and login
# -------------------------------------------------------------------

## Create test account
@email = @test.create_test_account
@email.include?('sessions-test')
#=> true

## Login with test account
@test.login(@email)
#=> true

# -------------------------------------------------------------------
# ACCOUNT INFO WITH ACTIVE SESSIONS COUNT
# -------------------------------------------------------------------

## Account info endpoint includes active_sessions_count
@test.get '/auth/account', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 200

## Response includes active_sessions_count field
@account_response = @test.json_response
@account_response.key?('active_sessions_count')
#=> true

## Active sessions count is at least 1 (current session)
@account_response['active_sessions_count'] >= 1
#=> true

# -------------------------------------------------------------------
# GET ACTIVE SESSIONS
# -------------------------------------------------------------------

## GET /auth/active-sessions requires authentication
@test.header 'Cookie', ''  # Clear cookies
@test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 401

## Login again to test sessions list
@test.login(@email)
#=> true

## GET /auth/active-sessions returns 200
@test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 200

## Response contains sessions array
@sessions_response = @test.json_response
@sessions_response.key?('sessions')
#=> true

## Sessions is an array
@sessions_response['sessions'].is_a?(Array)
#=> true

## At least one session exists (current session)
@sessions_response['sessions'].length >= 1
#=> true

## Current session is marked as is_current
@current_session = @sessions_response['sessions'].find { |s| s['is_current'] }
@current_session.nil? == false
#=> true

## Session has required fields
@session = @sessions_response['sessions'].first
@session.key?('id') && @session.key?('created_at') && @session.key?('last_activity_at')
#=> true

# -------------------------------------------------------------------
# DELETE SPECIFIC SESSION
# -------------------------------------------------------------------

## Cannot delete current session via DELETE endpoint
@current_session_id = @sessions_response['sessions'].find { |s| s['is_current'] }['id']
@test.delete "/auth/active-sessions/#{@current_session_id}", {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 400

## Error message indicates cannot remove current session
@error_response = @test.json_response
@error_response['error']&.include?('current session')
#=> true

# -------------------------------------------------------------------
# REMOVE ALL OTHER SESSIONS
# -------------------------------------------------------------------

## POST /auth/remove-all-active-sessions requires authentication
@test.header 'Cookie', ''
@test.post '/auth/remove-all-active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 401

## Login to test removing all sessions
@test.login(@email)
#=> true

## POST /auth/remove-all-active-sessions returns success
@test.post '/auth/remove-all-active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 200

## Response indicates success
@remove_response = @test.json_response
@remove_response.key?('success')
#=> true

## After removing all other sessions, only current session remains
@test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
@final_sessions = @test.json_response['sessions']
@final_sessions.length
#=> 1

## The remaining session is marked as current
@final_sessions.first['is_current']
#=> true

# -------------------------------------------------------------------
# CLEANUP
# -------------------------------------------------------------------

## Logout
@test.post '/auth/logout', {}, { 'HTTP_ACCEPT' => 'application/json' }
@test.last_response.status
#=> 200
