# try/60_logic/02a_logic_base_simple_try.rb

# Simple test for new RequestContext initialization pattern

require_relative '../test_logic'

# Load the app
OT.boot! :test, false

# Setup
@ctx = Otto::RequestContext.anonymous
@params = { test: 'value' }

## Test that Otto::RequestContext is available and works
@ctx.class
#=> Otto::RequestContext

## Test that our Logic base class can be initialized with RequestContext
@logic = V2::Logic::Base.new(@ctx, @params, 'en')
@logic.class
#=> V2::Logic::Base

## Test that the context is accessible
@logic.context.anonymous?
#=> true

## Test that session and user are extracted correctly from context
@logic.sess.class
#=> Hash

## Test that cust (user) is extracted correctly
@logic.cust.class
#=> Hash

## Test that locale is set properly
@logic.locale
#=> 'en'

## Test with authenticated context
@auth_ctx = Otto::RequestContext.new(
  session: { id: 'test123' },
  user: { name: 'testuser', id: 42 },
  auth_method: 'test',
  metadata: { ip: '127.0.0.1' }
)
@logic2 = V2::Logic::Base.new(@auth_ctx, @params, 'es')
@logic2.context.authenticated?
#=> true

## Test that user context is available
@logic2.cust[:name]
#=> 'testuser'

## Test that locale can be set
@logic2.locale
#=> 'es'
