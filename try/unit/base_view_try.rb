# try/unit/base_view_try.rb
#
# frozen_string_literal: true

#
# Test suite for Core::Views::BaseView nil strategy_result handling
#
# This test verifies that BaseView can be initialized in both scenarios:
# 1. Normal flow: strategy_result is present in request env (Otto ran)
# 2. Error recovery flow: strategy_result is nil, fallback params provided

# Setup - Load the real application
ENV['RACK_ENV'] = 'test'
ENV['AUTHENTICATION_MODE'] = 'basic'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

require 'rack/request'
require 'rack/mock'
require 'ostruct'

require_relative '../support/test_helpers'

require 'onetime'
require_relative '../../apps/web/core/views'

OT.boot! :test, false

# Setup for normal flow tests (using instance variables to persist across test cases)
@mock_session = { 'test_key' => 'test_value' }
@mock_user = Onetime::Customer.anonymous
@strategy_result = OpenStruct.new(
  session: @mock_session,
  user: @mock_user,
  authenticated?: true
)

env = Rack::MockRequest.env_for('http://example.com/')
env['otto.strategy_result'] = @strategy_result
env['otto.locale'] = 'en'
env['onetime.nonce'] = 'test-nonce'

req = Rack::Request.new(env)
@view = Core::Views::VuePoint.new(req)

## Normal flow extracts session from strategy_result
@view.sess
#=> @mock_session

## Normal flow extracts customer from strategy_result
@view.cust
#=> @mock_user

## Normal flow preserves strategy_result reference
@view.strategy_result
#=> @strategy_result

# Setup for error recovery flow tests
env_error = Rack::MockRequest.env_for('http://example.com/')
# Note: otto.strategy_result is intentionally missing (nil)
env_error['otto.locale'] = 'en'
env_error['onetime.nonce'] = 'test-nonce'

# Simulate ErrorHandling providing fallback values
@fallback_session = { 'fallback_key' => 'fallback_value' }
@fallback_cust = Onetime::Customer.anonymous
@fallback_locale = 'en'

req_error = Rack::Request.new(env_error)

# This should NOT crash even though strategy_result is nil
@view_error = Core::Views::VuePoint.new(req_error, @fallback_session, @fallback_cust, @fallback_locale)

## Error recovery view should not be nil after initialization
@view_error.nil?
#=> false

## Error recovery flow uses fallback session
@view_error.sess
#=> @fallback_session

## Error recovery flow uses fallback customer
@view_error.cust
#=> @fallback_cust

## Error recovery flow has nil strategy_result
@view_error.strategy_result
#=> nil

## Normal flow view_vars has authenticated customer
@view.view_vars['cust']
#=> @mock_user

## Normal flow view_vars shows authenticated
@view.view_vars['authenticated']
#=> true

## Error recovery flow view_vars has anonymous customer
@view_error.view_vars['cust']
#=> @fallback_cust

## Error recovery flow view_vars shows not authenticated
@view_error.view_vars['authenticated']
#=> false

## Normal flow serializers include authentication data
@view.serialized_data.keys.include?('authentication')
#=> true

## Normal flow serializers include config data
@view.serialized_data.keys.include?('config')
#=> true

## Error recovery flow serializers still work
@view_error.serialized_data.keys.include?('authentication')
#=> true

## Error recovery flow shows not authenticated in serialized data
@view_error.serialized_data['authentication']['authenticated']
#=> false

## Error recovery flow serializes customer data
@view_error.serialized_data['authentication']['cust']
#=:> Hash
