# try/unit/security/email_auth_rate_limiter_try.rb
#
# frozen_string_literal: true

# Audit 2026-08-02 finding L-5: EmailAuthRateLimiter caps unauthenticated
# magic-link requests per client IP. Rodauth's built-in
# email_auth_skip_resend_email_within throttle is PER ACCOUNT — it bounds
# resends for one mailbox but caps nothing across addresses, leaving mail
# dispatch unbounded per origin. This limiter is the additive per-IP tier.
#
# Single tier, keyed on the client IP alone: the per-mailbox bound already
# exists in Rodauth, so the gap is purely cross-address volume per origin —
# which only an IP tier caps.
#
# We test:
# 1. Under-limit requests are allowed; key shape and TTL
# 2. Over-limit raises LimitExceeded with the configured cap + lockout state
# 3. The limiter NEVER keys on the submitted login (enumeration safety)
# 4. nil/empty IP skips rather than sharing one global bucket
# 5. Cap-hit writes exactly one ColonelAuditEvent, and denied requests write no
#    further ones (bounded write frequency: one per masked network per window)
# 6. Garbage/non-positive config falls back to defaults instead of inverting
# 7. Configured-off (enabled:false) is a total no-op
# 8. The collapsed-IP operator hint is present and WIRED IN to the log line

require_relative '../../support/test_models'
require 'onetime/security/email_auth_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_email_auth_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['authentication'] ||= {}
  new_conf['site']['authentication']['email_auth_rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

# Toggle site.network.trusted_proxy.enabled for the collapsed-IP hint cases;
# the teardown restores @saved_conf wholesale.
def set_email_auth_trusted_proxy(value)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['network'] ||= {}
  new_conf['site']['network']['trusted_proxy'] = value.nil? ? {} : { 'enabled' => value }
  OT.send(:conf=, new_conf)
end

set_email_auth_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'window' => 900,
  'lockout' => 900,
)

class EmailAuthRateLimiterTester
  include Onetime::Security::EmailAuthRateLimiter
end

@tester = EmailAuthRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@ip_a = '203.0.113.10'
@ip_b = '198.51.100.20'

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip|
  @tester.enforce_email_auth_rate_limit!(ip)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup_email_auth_keys(redis, ip)
  redis.del("email_auth:attempts:ip:#{ip}", "email_auth:locked:ip:#{ip}")
end

cleanup_email_auth_keys(@redis, @ip_a)
cleanup_email_auth_keys(@redis, @ip_b)

## -- Under-limit ----------------------------------------------------------

## A single magic-link request under the cap is allowed
@raises.call(@ip_a)
#=> false

## The attempts counter uses the documented key shape (the one the ratelimit
## Registry and the bin/ots CLI emit commands for)
@redis.exists?("email_auth:attempts:ip:#{@ip_a}")
#=> true

## The counter carries a TTL within the configured window
ttl = @redis.ttl("email_auth:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## -- Enumeration safety ---------------------------------------------------

## The limiter keys ONLY on the IP: no key anywhere carries a submitted
## login. A login-derived key would make throttling observable per address —
## a registration-state oracle on a route whose response contract must not
## disclose one. Two requests from one IP for two different logins share one
## bucket and mint no login-keyed key.
@tester.enforce_email_auth_rate_limit!(@ip_b)
[@redis.get("email_auth:attempts:ip:#{@ip_b}").to_i,
 @redis.keys('email_auth:*@*').length]
#=> [1, 0]

## -- Over-limit (cap = 3) -------------------------------------------------

## Two more requests reach the cap (total 3) and lock the tier
[@raises.call(@ip_a), @raises.call(@ip_a)]
#=> [false, false]

## The lockout key is now set
@redis.exists?("email_auth:locked:ip:#{@ip_a}")
#=> true

## The attempts counter is cleared once the tier locks
@redis.exists?("email_auth:attempts:ip:#{@ip_a}")
#=> false

## The next request from that IP raises LimitExceeded
@raises.call(@ip_a)
#=> true

## The raised error reports the configured cap and a positive retry_after
begin
  @tester.enforce_email_auth_rate_limit!(@ip_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## A different IP is unaffected by that lockout
@raises.call(@ip_b)
#=> false

## -- Window expiry --------------------------------------------------------

## The lockout flag carries a TTL bounded by the configured lockout, so a
## locked tier frees itself once the window passes (no operator action needed)
lockout_ttl = @redis.ttl("email_auth:locked:ip:#{@ip_a}")
lockout_ttl.positive? && lockout_ttl <= 900
#=> true

## Expiry simulated by deleting the lockout key: the tier admits requests
## again and starts a fresh counter
cleanup_email_auth_keys(@redis, @ip_a)
[@raises.call(@ip_a), @redis.get("email_auth:attempts:ip:#{@ip_a}").to_i]
#=> [false, 1]

## -- Missing IP skips rather than sharing a global bucket -----------------

## A nil IP does not build a blank "ip:" key. Sharing one bucket across every
## IP-less caller would let the first few lock it and deny everyone after —
## a passwordless-login outage driven by whatever made the IP unresolvable.
result_nil = @raises.call(nil)
[result_nil, @redis.exists?('email_auth:attempts:ip:')]
#=> [false, false]

## An empty-string IP behaves identically
result_empty = @raises.call('')
[result_empty, @redis.exists?('email_auth:attempts:ip:')]
#=> [false, false]

## -- Audit trail ----------------------------------------------------------

## A cap-hit writes ONE queryable ColonelAuditEvent, so a magic-link flood
## leaves more than a log line. Counted as a delta rather than by clearing the
## shared store, which other tryout files also write to.
set_email_auth_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@audit_verb = Onetime::Security::EmailAuthRateLimiter::AUDIT_VERB
@audit_scan = lambda do
  if Onetime::ColonelAuditEvent.respond_to?(:recent_security)
    Onetime::ColonelAuditEvent.recent_security(500)
  else
    Onetime::ColonelAuditEvent.recent(500)
  end
end
@audit_count  = -> { @audit_scan.call.count { |e| e['verb'] == @audit_verb } }
@audit_ip     = '203.0.113.99'
cleanup_email_auth_keys(@redis, @audit_ip)
@audit_before = @audit_count.call
2.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## The event names the tier, the caps, and an unauthenticated actor
@audit_event = @audit_scan.call.find { |e| e['verb'] == @audit_verb }
[@audit_event['actor'], @audit_event['result'], @audit_event['detail']['tier'],
 @audit_event['detail']['count'], @audit_event['detail']['max_attempts']]
#=> ['anonymous', 'failure', 'ip', 2, 2]

## The target is the OBSCURED IP (/16), never the resolved one
@audit_event['target']
#=> 'ip:203.0.x.x'

## Denied requests write NO further events: only the cap-reaching request
## records, bounding writes to one per masked network per lockout window.
## Required of any unauthenticated writer into the audit store; keep it.
3.times { @raises.call(@audit_ip) }
@audit_count.call - @audit_before
#=> 1

## -- Config validation ----------------------------------------------------

## Non-positive / garbage numeric settings fall back to the defaults instead
## of inverting enforcement (a zero cap would otherwise lock on the very first
## request, and a non-positive lockout would make the Lua SETEX fail, turning
## every magic-link request into a 500 rather than a throttle)
set_email_auth_rate_limit(
  'enabled' => true, 'max_per_ip' => 0, 'window' => -5, 'lockout' => 'abc',
)
@cfg_ip = '198.51.100.77'
cleanup_email_auth_keys(@redis, @cfg_ip)
result_cfg = @raises.call(@cfg_ip)
[result_cfg, @redis.exists?("email_auth:locked:ip:#{@cfg_ip}")]
#=> [false, false]

## A PARTIAL config block — present, but with every numeric key absent — falls
## back to the defaults rather than raising (NilClass#to_i is 0, taking the
## same not-positive path as garbage)
set_email_auth_rate_limit('enabled' => true)
[@tester.send(:email_auth_max_per_ip),
 @tester.send(:email_auth_window),
 @tester.send(:email_auth_lockout)]
#=> [Onetime::Security::EmailAuthRateLimiter::DEFAULT_MAX_PER_IP, Onetime::Security::EmailAuthRateLimiter::DEFAULT_WINDOW, Onetime::Security::EmailAuthRateLimiter::DEFAULT_LOCKOUT]

## and it still enforces on those defaults rather than erroring
@partial_ip = '203.0.113.98'
cleanup_email_auth_keys(@redis, @partial_ip)
@raises.call(@partial_ip)
#=> false

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_email_auth_rate_limit('enabled' => false, 'max_per_ip' => 3)
@off_ip = '192.0.2.55'
cleanup_email_auth_keys(@redis, @off_ip)
results = (1..6).map { @raises.call(@off_ip) }
results.none?
#=> true

## A disabled limiter writes no keys at all
@redis.exists?("email_auth:attempts:ip:#{@off_ip}")
#=> false

## -- Collapsed IP operator hint (log line only) ---------------------------

## Without a declared trusted proxy the resolved client IP is REMOTE_ADDR, so
## a lockout may be deployment-wide — which for THIS limiter means
## passwordless login is shut off for every visitor. The hint says so and
## names the remedy inline. It is appended to a server LOG line, never to a
## response.
set_email_auth_trusted_proxy(false)
hint = @tester.send(:collapsed_email_auth_ip_hint)
[hint.empty?, hint.include?('trusted_proxy'), hint.include?('TRUSTED_PROXY_ENABLED=true')]
#=> [false, true, true]

## An absent trusted_proxy config reads the same as disabled
set_email_auth_trusted_proxy(nil)
@tester.send(:collapsed_email_auth_ip_hint).match?(/trusted_proxy/)
#=> true

## With the trusted proxy declared the hint is empty, so a correctly
## configured deployment's lockout line stays byte-identical
set_email_auth_trusted_proxy(true)
@tester.send(:collapsed_email_auth_ip_hint)
#=> ""

## The hint is WIRED IN: a REAL cap hit (trusted proxy not declared) emits
## exactly one OT.le line carrying both the cap text and the hint. The three
## cases above call the private helper directly, so they stay green even if
## the interpolation is dropped from enforce_email_auth_rate_limit!; this
## case is the one that fails.
set_email_auth_trusted_proxy(false)
set_email_auth_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'window' => 900, 'lockout' => 900,
)
@hint_ip = '192.0.2.99'
cleanup_email_auth_keys(@redis, @hint_ip)
captured = []
OT.singleton_class.alias_method(:__ea_hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  2.times { @tester.enforce_email_auth_rate_limit!(@hint_ip) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__ea_hint_real_le)
  OT.singleton_class.remove_method(:__ea_hint_real_le)
end
line = captured.find { |msg| msg.include?('hit cap') }.to_s
[
  captured.length,
  line.include?('[EmailAuthRateLimiter] ip'),
  line.include?('hit cap (2/2)'),
  line.include?('TRUSTED_PROXY_ENABLED=true'),
]
#=> [1, true, true, true]

## With the trusted proxy declared the same cap hit logs WITHOUT the hint
set_email_auth_trusted_proxy(true)
@hint_ip_ok = '192.0.2.100'
cleanup_email_auth_keys(@redis, @hint_ip_ok)
captured_ok = []
OT.singleton_class.alias_method(:__ea_hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured_ok << msgs.join(' ') }
begin
  2.times { @tester.enforce_email_auth_rate_limit!(@hint_ip_ok) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__ea_hint_real_le)
  OT.singleton_class.remove_method(:__ea_hint_real_le)
end
line_ok = captured_ok.find { |msg| msg.include?('hit cap') }.to_s
[line_ok.end_with?('locked for 900s'), line_ok.include?('TRUSTED_PROXY_ENABLED')]
#=> [true, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup_email_auth_keys(@redis, @ip_a)
cleanup_email_auth_keys(@redis, @ip_b)
cleanup_email_auth_keys(@redis, @audit_ip)
cleanup_email_auth_keys(@redis, @cfg_ip)
cleanup_email_auth_keys(@redis, @partial_ip)
cleanup_email_auth_keys(@redis, @off_ip)
cleanup_email_auth_keys(@redis, @hint_ip)
cleanup_email_auth_keys(@redis, @hint_ip_ok)
OT.send(:conf=, @saved_conf)
