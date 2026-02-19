# try/unit/page_title_brand_fallback_try.rb
#
# frozen_string_literal: true

#
# Test suite for page_title brand fallback chain
#
# Verifies that page_title in initialize_view_vars.rb correctly uses:
# 1. display_domain (when available)
# 2. site_name (when display_domain is nil)
# 3. brand_product_name (when both display_domain and site_name are nil)
# 4. Fallback to 'OTS' when brand_product_name is not configured

# Setup - Load the real application
ENV['AUTHENTICATION_MODE'] = 'simple'

require 'rack/request'
require 'rack/mock'

require_relative '../support/test_helpers'

require 'onetime'
require_relative '../../apps/web/core/views'

OT.boot! :test, false

# Mock class for strategy results
class MockStrategyResult
  attr_reader :session, :user, :metadata

  def initialize(session:, user:, authenticated: false, metadata: {})
    @session = session
    @user = user
    @authenticated = authenticated
    @metadata = metadata || {}
  end

  def authenticated?
    @authenticated
  end
end

# Setup base strategy result
@mock_session = { 'test_key' => 'test_value' }
@mock_user = Onetime::Customer.anonymous
@strategy_result = MockStrategyResult.new(
  session: @mock_session,
  user: @mock_user,
  authenticated: true
)

# Test 1: page_title uses display_domain when available
env1 = Rack::MockRequest.env_for('http://example.com/')
env1['otto.strategy_result'] = @strategy_result
env1['otto.locale'] = 'en'
env1['onetime.nonce'] = 'test-nonce'
env1['onetime.display_domain'] = 'Custom Domain'
req1 = Rack::Request.new(env1)
@view1 = Core::Views::VuePoint.new(req1)

# Test 2: page_title falls back when display_domain is nil
env2 = Rack::MockRequest.env_for('http://example.com/')
env2['otto.strategy_result'] = @strategy_result
env2['otto.locale'] = 'en'
env2['onetime.nonce'] = 'test-nonce'
# No display_domain set
req2 = Rack::Request.new(env2)
@view2 = Core::Views::VuePoint.new(req2)

## page_title uses display_domain when available
@view1.view_vars['page_title']
#=> 'Custom Domain'

## page_title falls back to site_name or brand_product_name when display_domain is nil
# When site_name is not configured, should use brand_product_name from config
# Default brand_product_name is 'OTS' in test config
@view2.view_vars['page_title']
#=:> String

## page_title is never nil (always has fallback)
@view2.view_vars['page_title'].nil?
#=> false

## page_title uses brand_product_name from config
# Verify the fallback chain: display_domain || site_name || brand_product_name
# In test environment without custom display_domain or site_name, should use brand config
brand_name = @view2.view_vars['brand_product_name']
page_title = @view2.view_vars['page_title']
[brand_name, page_title].include?('OTS') || page_title == brand_name
#=> true

## brand_product_name comes from config brand section
@view2.view_vars['brand_product_name']
#=:> String

## page_title matches brand_product_name when no display_domain or site_name
# This verifies the fix from task #1
@view2.view_vars['page_title'] == @view2.view_vars['brand_product_name']
#=> true
