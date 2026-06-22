# One-shot reveal worker (separate OS process => true parallelism, no shared GIL).
# Boots, waits for a shared wall-clock deadline, then runs the real reveal
# sequence once and reports whether it obtained the plaintext.
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

id       = File.read('/home/user/security-assessment/evidence/secret_id.txt').strip
deadline = File.read('/home/user/security-assessment/evidence/deadline.txt').strip.to_f

# Pre-load the secret instance, then spin-wait to the shared deadline so all
# processes hit the consume within the same millisecond.
s = Onetime::Secret.load(id)
viewable = s && s.viewable?
sleep 0.001 while Process.clock_gettime(Process::CLOCK_REALTIME) < deadline

got = false
if viewable
  val = s.decrypted_secret_value
  s.revealed!
  got = !val.to_s.empty?
end
puts "WORKER pid=#{Process.pid} viewable=#{!!viewable} got=#{got}"
