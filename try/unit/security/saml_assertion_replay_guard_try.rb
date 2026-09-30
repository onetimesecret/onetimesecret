# try/unit/security/saml_assertion_replay_guard_try.rb
#
# frozen_string_literal: true

# #4450: SamlAssertionReplayGuard is the SP-side "set of used assertion IDs"
# SAML Core requires for bearer assertions. One atomic SET NX EX per
# (idp_entity_id, assertion_id) against the REAL test datastore.
#
# We test:
# 1. First claim succeeds, second claim of the same assertion is refused
# 2. The key carries a TTL derived from NotOnOrAfter + clock drift
# 3. Key shape: prefix + sha256, no IdP-controlled bytes in the keyspace
# 4. The same assertion id under a different IdP is an independent claim
# 5. TTL floor (already-expired NotOnOrAfter) and the TTL cap a caller that
#    skipped lifetime_exceeded? still hits (far-future)
# 6. Once the key expires the id can be claimed again (proof the EX is what
#    releases it)
# 7. Blank identifiers / non-Time expiry raise rather than claim
# 8. lifetime_exceeded? is what the strategy refuses on: a one-hour
#    assertion passes (with drift), anything longer does not
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only try/unit/security/saml_assertion_replay_guard_try.rb

require_relative '../../support/test_models'
require 'onetime/security/saml_assertion_replay_guard'

OT.boot! :test, true

@guard = Onetime::Security::SamlAssertionReplayGuard
@redis = Familia.dbclient
@run   = SecureRandom.hex(6)
@idp_a = "https://idp-a.example.com/metadata/#{@run}"
@idp_b = "https://idp-b.example.com/metadata/#{@run}"
@aid   = "_assertion-#{@run}"
@now   = Time.now
@keys  = []

def claim_for(idp, aid, not_on_or_after, drift: 60)
  @keys << @guard.key_for(idp, aid)
  @guard.claim(idp_entity_id: idp, assertion_id: aid, not_on_or_after: not_on_or_after, clock_drift: drift, now: @now)
end

## first presentation claims the assertion
claim_for(@idp_a, @aid, @now + 300)
#=> true

## second presentation of the same assertion is refused
claim_for(@idp_a, @aid, @now + 300)
#=> false

## a third is still refused (the refusal does not reset anything)
claim_for(@idp_a, @aid, @now + 300)
#=> false

## the key exists with value '1'
@redis.get(@guard.key_for(@idp_a, @aid))
#=> '1'

## TTL = (NotOnOrAfter - now) + drift = 360s (allow a couple of seconds of wall clock)
ttl = @redis.ttl(@guard.key_for(@idp_a, @aid))
ttl.between?(355, 360)
#=> true

## a refused replay does not extend the TTL of the original claim
claim_for(@idp_a, @aid, @now + 3000)
@redis.ttl(@guard.key_for(@idp_a, @aid)) <= 360
#=> true

## key shape: fixed prefix + 64 hex chars, nothing IdP-controlled in it
key = @guard.key_for(@idp_a, @aid)
[key.match?(/\Asaml:assertion:[0-9a-f]{64}\z/), key.include?(@run)]
#=> [true, false]

## the same assertion id from a different IdP is an independent claim
claim_for(@idp_b, @aid, @now + 300)
#=> true

## length-prefixed digest: moving bytes across the boundary changes the key
@guard.key_for('ab', 'c') == @guard.key_for('a', 'bc')
#=> false

## an already-expired NotOnOrAfter still records the claim, at the 1s floor
claim_for(@idp_a, "#{@aid}-expired", @now - 600, drift: 0)
@redis.ttl(@guard.key_for(@idp_a, "#{@aid}-expired")).between?(0, 1)
#=> true

## a far-future NotOnOrAfter is capped at max_ttl_for(drift) (= MAX_LIFETIME + 2 x drift)
claim_for(@idp_a, "#{@aid}-far", @now + (86_400 * 365))
@redis.ttl(@guard.key_for(@idp_a, "#{@aid}-far")).between?(@guard.max_ttl_for(60) - 5, @guard.max_ttl_for(60))
#=> true

## the longest lifetime the strategy admits is one hour plus the drift
@guard.lifetime_exceeded?(@now + @guard::MAX_LIFETIME + 60, clock_drift: 60, now: @now)
#=> false

## one second past that is refused by the caller before any claim
@guard.lifetime_exceeded?(@now + @guard::MAX_LIFETIME + 61, clock_drift: 60, now: @now)
#=> true

## an admitted one-hour assertion's key is NOT clamped: it outlives the gem's window (3600 + 2 x 60)
claim_for(@idp_a, "#{@aid}-hour", @now + @guard::MAX_LIFETIME + 60)
@redis.ttl(@guard.key_for(@idp_a, "#{@aid}-hour")).between?(3715, 3720)
#=> true

## after the key expires the id is claimable again (EX is what releases it)
sleep 1.2 # the floor-TTL key above lives 1s; let the datastore expire it
claim_for(@idp_a, "#{@aid}-expired", @now + 300)
#=> true

## blank assertion id raises instead of claiming the digest of ''
begin
  @guard.claim(idp_entity_id: @idp_a, assertion_id: ' ', not_on_or_after: @now + 300)
rescue ArgumentError => ex
  ex.message
end
#=> 'assertion_id is blank'

## blank idp entity id raises
begin
  @guard.claim(idp_entity_id: nil, assertion_id: @aid, not_on_or_after: @now + 300)
rescue ArgumentError => ex
  ex.message
end
#=> 'idp_entity_id is blank'

## nil NotOnOrAfter raises (no TTL can be derived, so no claim is made)
begin
  @guard.claim(idp_entity_id: @idp_a, assertion_id: "#{@aid}-nil", not_on_or_after: nil)
rescue ArgumentError => ex
  [ex.message, @redis.exists?(@guard.key_for(@idp_a, "#{@aid}-nil"))]
end
#=> ['not_on_or_after must be a Time', false]

# Remove every key this file created.
@keys.uniq.each { |key| @redis.del(key) }
