# Dumps actual response headers from the running stack to confirm which
# security headers are present on a DEFAULT install (no MIDDLEWARE_* / CSP_ENABLED set).
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
ENV['RACK_ENV']                 ||= 'development'
ENV['ONETIME_HOME']               = '/home/user/onetimesecret'
ENV['SECRET']                   ||= File.read('/home/user/security-assessment/notes/.test_secret').strip
ENV['REDIS_URL']                ||= 'redis://127.0.0.1:6379/0'
ENV['IDENTIFIER_SECRET']        ||= 'a' * 64
ENV['VERIFIABLE_ID_HMAC_SECRET']||= ENV['IDENTIFIER_SECRET']
ENV['HOST']                     ||= 'localhost:3000'
$LOAD_PATH.unshift('/home/user/onetimesecret/lib')
require 'onetime'
OT.execution_mode = :backend
Onetime.boot! :app
Onetime::Application::Registry.prepare_application_registry
APP = Onetime::Application::Registry.generate_rack_url_map
begin; require 'semantic_logger'; SemanticLogger.default_level = :fatal; rescue StandardError; end
require 'rack/mock'

SECURITY_HEADERS = [
  'content-security-policy', 'x-frame-options', 'strict-transport-security',
  'x-content-type-options', 'x-xss-protection', 'referrer-policy',
  'cross-origin-opener-policy', 'access-control-allow-origin', 'set-cookie',
]

['/api/v2/status', '/'].each do |path|
  env = Rack::MockRequest.env_for(path, method: 'GET', 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_HOST' => 'localhost:3000')
  status, headers, _ = APP.call(env)
  h = {}; headers.each { |k, v| h[k.downcase] = v }
  puts "\n=== GET #{path}  -> HTTP #{status} ==="
  SECURITY_HEADERS.each do |hd|
    puts format("  %-30s %s", hd + ':', h.key?(hd) ? h[hd].to_s[0, 80] : '<ABSENT>')
  end
end
