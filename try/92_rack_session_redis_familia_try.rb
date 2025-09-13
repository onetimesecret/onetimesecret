# try/92_rack_session_redis_familia_try.rb

require_relative 'test_helpers'
require_relative '../lib/rack/session/redis_familia'
require 'rack/test'
require 'rack/mock'
require 'cgi'

OT.boot! :test, false

@test_app = lambda { |env|
  session = env['onetime.session']

  case env['PATH_INFO']
  when '/set'
    session['test_key'] = 'test_value'
    session['identity_id'] = 'user123'
    session['tenant_id'] = 'tenant456'
    [200, {'Content-Type' => 'text/plain'}, ['Session set']]
  when '/get'
    value = session['test_key']
    [200, {'Content-Type' => 'text/plain'}, [value.to_s]]
  when '/destroy'
    env['rack.session.options'][:drop] = true
    [200, {'Content-Type' => 'text/plain'}, ['Session destroyed']]
  else
    [200, {'Content-Type' => 'text/plain'}, ['OK']]
  end
}

@session_app = Rack::Session::RedisFamilia.new(@test_app, {
  expire_after: 60,
  redis_prefix: 'test:session'
})

## RedisFamilia session store generates unique session IDs
session_store = Rack::Session::RedisFamilia.new(@test_app)
sid1 = session_store.generate_sid
sid2 = session_store.generate_sid
sid1 != sid2
#=> true

## Session ID has proper length and format
session_store = Rack::Session::RedisFamilia.new(@test_app)
sid = session_store.generate_sid
sid.length >= 32 && sid.match?(/^[A-Za-z0-9_-]+$/)
#=> true

## Session can be created and retrieved using Rack::Test
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
browser.last_response.status == 200
#=> true

## Session persists across requests
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
cookie = browser.last_response.headers['Set-Cookie']
browser.set_cookie(cookie) if cookie
browser.get '/get'
browser.last_response.body
#=> "test_value"

## Session data is stored in Redis with proper key format
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
cookie = browser.last_response.headers['Set-Cookie']
sid = cookie&.match(/ots\.session=([^;]+)/)&.captures&.first
sid = CGI.unescape(sid) if sid
redis_key = "test:session:#{sid}" if sid
stored_data = Familia.dbclient.get(redis_key) if redis_key
parsed = JSON.parse(stored_data) if stored_data
parsed && parsed['data'] && parsed['data']['test_key'] == 'test_value'
#=> true

## Session includes metadata fields
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
cookie = browser.last_response.headers['Set-Cookie']
sid = cookie&.match(/ots\.session=([^;]+)/)&.captures&.first
sid = CGI.unescape(sid) if sid
redis_key = "test:session:#{sid}" if sid
stored_data = Familia.dbclient.get(redis_key) if redis_key
parsed = JSON.parse(stored_data) if stored_data
parsed && parsed['identity_id'] == 'user123' && parsed['tenant_id'] == 'tenant456'
#=> true

## Session has proper TTL set in Redis
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
cookie = browser.last_response.headers['Set-Cookie']
sid = cookie&.match(/ots\.session=([^;]+)/)&.captures&.first
sid = CGI.unescape(sid) if sid
redis_key = "test:session:#{sid}" if sid
ttl = Familia.dbclient.ttl(redis_key) if redis_key
ttl && ttl > 0 && ttl <= 60
#=> true

## Session can be destroyed
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
cookie = browser.last_response.headers['Set-Cookie']
sid = cookie&.match(/ots\.session=([^;]+)/)&.captures&.first
sid = CGI.unescape(sid) if sid
browser.get '/destroy'
redis_key = "test:session:#{sid}" if sid
exists = Familia.dbclient.exists?(redis_key) if redis_key
!exists
#=> true

## No new session ID is generated after destroy with drop option
browser = Rack::Test::Session.new(@session_app)
browser.get '/set'
first_cookie = browser.last_response.headers['Set-Cookie']
browser.get '/destroy'
second_cookie = browser.last_response.headers['Set-Cookie']
# After destroy with drop: true, no new session cookie should be set
second_sid = second_cookie&.match(/ots\.session=([^;]+)/)&.captures&.first
second_sid.nil?
#=> true

## Session handles missing or invalid session gracefully
invalid_sid = 'invalid_session_id_12345'
env = Rack::MockRequest.env_for('/', 'HTTP_COOKIE' => "ots.session=#{invalid_sid}")
status, headers, body = @session_app.call(env)
status == 200
#=> true

Familia.dbclient.flushdb if Familia.dbclient.dbsize < 100
