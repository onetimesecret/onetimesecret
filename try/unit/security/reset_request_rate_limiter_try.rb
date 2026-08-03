# try/unit/security/reset_request_rate_limiter_try.rb
#
# frozen_string_literal: true

# #3872: ResetRequestRateLimiter throttles reset-password-request submissions,
# bounding the sampling throughput of the timing residual accepted by the
# enumeration-safe route (#3857). Two tiers, mirroring IncomingRateLimiter:
#   1. Per-IP tier    - the tight gate (max_per_ip per window).
#   2. Per-email tier - a higher backstop keyed on the NORMALIZED submitted
#                       login (catches IP-rotating callers).
#
# We test:
# 1. Under-limit requests are allowed
# 2. Key shape and TTL of the per-IP attempts counter
# 3. Over-limit raises LimitExceeded with the configured cap + lockout state
# 4. Login normalization (Rodauth-parity: case/whitespace variants, Unicode
#    case-folding, and control characters all land in one bucket)
# 5. nil-IP falls back to the per-email tier only
# 6. The per-email backstop caps IP-rotating callers
# 7. Configured-off (enabled:false) is a total no-op

require_relative '../../support/test_models'
require 'onetime/security/reset_request_rate_limiter'

OT.boot! :test, true

# Tryout files share one process and OT.conf is global; snapshot the booted
# config so the teardown can restore it for later files.
@saved_conf = YAML.load(YAML.dump(OT.conf))

# Enable the limiter with small, known caps (test config ships it disabled).
def set_reset_request_rate_limit(cfg)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['authentication'] ||= {}
  new_conf['site']['authentication']['reset_request_rate_limit'] = cfg
  OT.send(:conf=, new_conf)
end

# Toggle site.network.trusted_proxy.enabled for the collapsed-IP-tier hint
# cases; the teardown restores @saved_conf wholesale.
def set_trusted_proxy_enabled(value)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['site'] ||= {}
  new_conf['site']['network'] ||= {}
  new_conf['site']['network']['trusted_proxy'] = value.nil? ? {} : { 'enabled' => value }
  OT.send(:conf=, new_conf)
end

set_reset_request_rate_limit(
  'enabled' => true,
  'max_per_ip' => 3,
  'max_per_email' => 5,
  'window' => 900,
  'lockout' => 900,
)

class ResetRequestRateLimiterTester
  include Onetime::Security::ResetRequestRateLimiter
end

@tester = ResetRequestRateLimiterTester.new
@redis  = Onetime::Customer.dbclient

@ip_a    = '203.0.113.10'
@ip_b    = '198.51.100.20'
@tag     = "#{Familia.now.to_i}_#{rand(10_000)}"
@email_a = "target_a_#{@tag}@example.com"
@email_b = "target_b_#{@tag}@example.com"
@email_c = "target_c_#{@tag}@example.com"
# The bucket an eszett-variant login must case-fold into (U+00DF folds to
# "ss").
@email_fold = "fold_ss_#{@tag}@example.com"

# true if a single enforce call raises LimitExceeded, false otherwise.
@raises = lambda do |ip, login = nil|
  @tester.enforce_reset_request_rate_limit!(ip, login)
  false
rescue Onetime::LimitExceeded
  true
end

def cleanup(redis, ip: nil, email: nil)
  keys = []
  keys += ["reset_request:attempts:ip:#{ip}", "reset_request:locked:ip:#{ip}"] if ip
  keys += ["reset_request:attempts:email:#{email}", "reset_request:locked:email:#{email}"] if email
  redis.del(*keys) unless keys.empty?
end

cleanup(@redis, ip: @ip_a, email: @email_a)
cleanup(@redis, ip: @ip_b, email: @email_b)
cleanup(@redis, email: @email_c)
cleanup(@redis, email: @email_fold)

## -- Under-limit ----------------------------------------------------------

## A single request under the cap is allowed
@raises.call(@ip_a, @email_a)
#=> false

## The per-IP attempts counter uses the documented key shape
@redis.exists?("reset_request:attempts:ip:#{@ip_a}")
#=> true

## The per-IP counter carries a TTL within the configured window
ttl = @redis.ttl("reset_request:attempts:ip:#{@ip_a}")
ttl.positive? && ttl <= 900
#=> true

## The per-email counter is also written on the same request
@redis.exists?("reset_request:attempts:email:#{@email_a}")
#=> true

## -- Login normalization --------------------------------------------------

## Case/whitespace variants of one target land in the SAME per-email bucket
@tester.enforce_reset_request_rate_limit!(@ip_b, "  #{@email_a.upcase}  ")
@redis.get("reset_request:attempts:email:#{@email_a}").to_i
#=> 2

## Unicode case-folding and control characters cannot dodge the bucket either:
## normalization mirrors Rodauth's normalize_login (OT::Utils.normalize_email,
## NFC + case-fold), so an eszett (U+00DF) variant with an embedded control
## character folds into the plain-ss bucket Rodauth would resolve the account
## from
@tester.enforce_reset_request_rate_limit!(nil, "\u0000fold_\u00df_#{@tag}@EXAMPLE.com\r\n")
@redis.get("reset_request:attempts:email:#{@email_fold}").to_i
#=> 1

## -- Over-limit (per-IP tier trips first at max_per_ip=3) -----------------

## Two more requests reach the per-IP cap (total 3) and lock the IP tier
[@raises.call(@ip_a, @email_a), @raises.call(@ip_a, @email_a)]
#=> [false, false]

## The per-IP lockout key is now set
@redis.exists?("reset_request:locked:ip:#{@ip_a}")
#=> true

## The per-IP attempts counter is cleared once the tier locks
@redis.exists?("reset_request:attempts:ip:#{@ip_a}")
#=> false

## The next request from that IP raises LimitExceeded
@raises.call(@ip_a, @email_a)
#=> true

## The raised error reports the per-IP cap and a positive retry_after
begin
  @tester.enforce_reset_request_rate_limit!(@ip_a, @email_a)
  nil
rescue Onetime::LimitExceeded => e
  [e.max_attempts, e.retry_after.positive?]
end
#=> [3, true]

## -- nil-IP falls back to the per-email tier only -------------------------

## A nil-IP request does not build a blank "ip:" key
@raises.call(nil, @email_c)
[@redis.exists?("reset_request:attempts:ip:"), @redis.exists?("reset_request:attempts:email:#{@email_c}")]
#=> [false, true]

## With neither IP nor login the limiter is a complete no-op: no raise,
## and neither tier writes a blank-suffixed key
result = @raises.call(nil, nil)
[result, @redis.exists?("reset_request:attempts:ip:"), @redis.exists?("reset_request:attempts:email:")]
#=> [false, false, false]

## -- Per-email backstop (max_per_email=5) ---------------------------------

## Five nil-IP requests reach the per-email cap and lock the email tier
cleanup(@redis, email: @email_b)
5.times { @tester.enforce_reset_request_rate_limit!(nil, @email_b) }
@redis.exists?("reset_request:locked:email:#{@email_b}")
#=> true

## The next request for that login raises, reporting the per-email cap
begin
  @tester.enforce_reset_request_rate_limit!(nil, @email_b)
  nil
rescue Onetime::LimitExceeded => e
  e.max_attempts
end
#=> 5

## An IP-rotating caller (fresh IP each time) is still capped by the email tier
@raises.call(@ip_b, @email_b)
#=> true

## -- Audit trail --------------------------------------------------------

## A cap-hit writes ONE queryable ColonelAuditEvent, so an enumeration attempt
## leaves more than a log line. Counted as a delta rather than by clearing the
## shared store, which other tryout files also write to.
set_reset_request_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'max_per_email' => 50,
  'window' => 900, 'lockout' => 900,
)
@audit_verb  = Onetime::Security::ResetRequestRateLimiter::AUDIT_VERB
@audit_count = -> { Onetime::ColonelAuditEvent.recent_security(500).count { |e| e['verb'] == @audit_verb } }
@admin_count = -> { Onetime::ColonelAuditEvent.count }
@audit_ip    = '203.0.113.99'
@audit_email = "target_audit_#{@tag}@example.com"
cleanup(@redis, ip: @audit_ip, email: @audit_email)
@audit_before = @audit_count.call
@admin_before = @admin_count.call
2.times { @raises.call(@audit_ip, @audit_email) }
@audit_count.call - @audit_before
#=> 1

## The event lands in the SECURITY trail, never the operator trail. That trail
## is count-capped with no TTL and evicts oldest-first, so an unauthenticated
## writer sharing it could flush purge/role-change/suspension records.
@admin_count.call - @admin_before
#=> 0

## The event names the tier, the caps, and an unauthenticated actor
@audit_event = Onetime::ColonelAuditEvent.recent_security(500).find { |e| e['verb'] == @audit_verb }
[@audit_event['actor'], @audit_event['result'], @audit_event['detail']['tier'],
 @audit_event['detail']['count'], @audit_event['detail']['max_attempts']]
#=> ['anonymous', 'failure', 'ip', 2, 2]

## The target is the OBSCURED subject — the audit trail must not become the
## enumeration oracle the limiter exists to bound
@audit_event['target']
#=> 'ip:203.0.x.x'

## Denied requests write NO further events: only the cap-reaching request
## records, so writes are bounded to one per bucket per lockout window. This is
## a SIGNAL-quality bound (a per-request event is noise); the integrity of the
## operator trail rests on the separate collection, not on this frequency.
3.times { @raises.call(@audit_ip, @audit_email) }
@audit_count.call - @audit_before
#=> 1

## ...and the flood still leaves the operator trail untouched
@admin_count.call - @admin_before
#=> 0

## -- Config validation ----------------------------------------------------

## Non-positive / garbage numeric settings fall back to the defaults instead
## of inverting enforcement (a zero cap would otherwise lock on the very
## first request, and a non-positive lockout would make the Lua SETEX fail)
set_reset_request_rate_limit(
  'enabled' => true, 'max_per_ip' => 0, 'max_per_email' => 'abc',
  'window' => -5, 'lockout' => 0,
)
@cfg_ip    = '198.51.100.77'
@cfg_email = "target_cfg_#{@tag}@example.com"
cleanup(@redis, ip: @cfg_ip, email: @cfg_email)
result = @raises.call(@cfg_ip, @cfg_email)
[result, @redis.exists?("reset_request:locked:ip:#{@cfg_ip}")]
#=> [false, false]

## -- Configured off -------------------------------------------------------

## With enabled:false the limiter is a total no-op even past the caps
set_reset_request_rate_limit('enabled' => false, 'max_per_ip' => 3, 'max_per_email' => 5)
@off_ip    = '192.0.2.55'
@off_email = "target_off_#{Familia.now.to_i}_#{rand(10_000)}@example.com"
cleanup(@redis, ip: @off_ip, email: @off_email)
results = (1..6).map { @raises.call(@off_ip, @off_email) }
results.none?
#=> true

## Disabled limiter writes no keys at all
[@redis.exists?("reset_request:attempts:ip:#{@off_ip}"), @redis.exists?("reset_request:attempts:email:#{@off_email}")]
#=> [false, false]

## -- Collapsed IP-tier operator hint (log line only) ----------------------

## Without a declared trusted proxy the resolved client IP is REMOTE_ADDR, so
## an IP-tier lockout may be deployment-wide; the hint says so and names the
## remedy. It is appended to a server LOG line, never to a response.
set_trusted_proxy_enabled(false)
hint = @tester.send(:collapsed_ip_tier_hint, 'ip')
[hint.empty?, hint.include?('trusted_proxy'), hint.include?('TRUSTED_PROXY_ENABLED=true')]
#=> [false, true, true]

## An absent trusted_proxy config reads the same as disabled
set_trusted_proxy_enabled(nil)
@tester.send(:collapsed_ip_tier_hint, 'ip').match?(/trusted_proxy/)
#=> true

## With the trusted proxy declared the hint is empty: the IP tier is granular,
## so the lockout log line stays byte-identical to before
set_trusted_proxy_enabled(true)
@tester.send(:collapsed_ip_tier_hint, 'ip')
#=> ""

## The email backstop never carries the hint - it does not key on IP, in either
## trusted-proxy state
[false, true].map do |enabled|
  set_trusted_proxy_enabled(enabled)
  @tester.send(:collapsed_ip_tier_hint, 'email')
end
#=> ["", ""]

## The hint is WIRED IN: a REAL IP-tier cap hit (trusted proxy not declared)
## emits exactly one OT.le line, and that line carries both the cap text and
## the hint. The four cases above call the private helper directly, so they
## stay green even if the interpolation is dropped from
## enforce_reset_request_tier!; this case is the one that fails. OT.le is
## swapped on the singleton class and restored in an ensure (the stub/restore
## shape used by try/integration/api/colonel/upsert_domain_config_race_try.rb).
set_trusted_proxy_enabled(false)
set_reset_request_rate_limit(
  'enabled' => true, 'max_per_ip' => 2, 'max_per_email' => 50,
  'window' => 900, 'lockout' => 900,
)
@hint_ip    = '192.0.2.99'
@hint_email = "target_hint_#{@tag}@example.com"
cleanup(@redis, ip: @hint_ip, email: @hint_email)
captured = []
OT.singleton_class.alias_method(:__hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured << msgs.join(' ') }
begin
  # Second request reaches max_per_ip=2 and locks the IP tier; the email tier
  # (cap 50) stays far from its own threshold, so nothing else logs.
  2.times { @tester.enforce_reset_request_rate_limit!(@hint_ip, @hint_email) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__hint_real_le)
  OT.singleton_class.remove_method(:__hint_real_le)
end
line = captured.find { |msg| msg.include?('hit cap') }.to_s
[
  captured.length,
  line.include?('[ResetRequestRateLimiter] ip'),
  line.include?('hit cap (2/2)'),
  line.include?('site.network.trusted_proxy is not enabled'),
  line.include?('TRUSTED_PROXY_ENABLED=true'),
]
#=> [1, true, true, true, true]

## The same real cap hit WITH a declared trusted proxy logs the bare cap line:
## the hint is absent, so a correctly configured deployment is unchanged
set_trusted_proxy_enabled(true)
@hint_ip_ok    = '192.0.2.100'
@hint_email_ok = "target_hint_ok_#{@tag}@example.com"
cleanup(@redis, ip: @hint_ip_ok, email: @hint_email_ok)
captured_ok = []
OT.singleton_class.alias_method(:__hint_real_le, :le)
OT.define_singleton_method(:le) { |*msgs, **_payload| captured_ok << msgs.join(' ') }
begin
  2.times { @tester.enforce_reset_request_rate_limit!(@hint_ip_ok, @hint_email_ok) }
ensure
  OT.singleton_class.remove_method(:le)
  OT.singleton_class.alias_method(:le, :__hint_real_le)
  OT.singleton_class.remove_method(:__hint_real_le)
end
line_ok = captured_ok.find { |msg| msg.include?('hit cap') }.to_s
[line_ok.end_with?('locked for 900s'), line_ok.include?('TRUSTED_PROXY_ENABLED')]
#=> [true, false]

# Clean up test keys and restore the shared config for later tryout files.
cleanup(@redis, ip: @ip_a, email: @email_a)
cleanup(@redis, ip: @ip_b, email: @email_b)
cleanup(@redis, email: @email_c)
cleanup(@redis, email: @email_fold)
cleanup(@redis, ip: @cfg_ip, email: @cfg_email)
cleanup(@redis, ip: @off_ip, email: @off_email)
cleanup(@redis, ip: @hint_ip, email: @hint_email)
cleanup(@redis, ip: @hint_ip_ok, email: @hint_email_ok)
cleanup(@redis, ip: @audit_ip, email: @audit_email)
OT.send(:conf=, @saved_conf)
