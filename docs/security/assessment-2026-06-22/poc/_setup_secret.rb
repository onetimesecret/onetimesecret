# Creates one secret and writes its id for the multi-process race workers.
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
begin; require 'semantic_logger'; SemanticLogger.default_level = :fatal; rescue StandardError; end

s = Onetime::Secret.new
s.objid
s.state = 'new'; s.owner_id = 'anon'; s.lifespan = 3600
s.ciphertext = "RACE-CANARY-#{Time.now.to_i}-#{rand(1_000_000)}"
s.save
File.write('/home/user/security-assessment/evidence/secret_id.txt', s.identifier)
puts "created #{s.identifier}"
