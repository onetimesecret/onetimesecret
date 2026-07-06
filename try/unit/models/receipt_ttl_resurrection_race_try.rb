# try/unit/models/receipt_ttl_resurrection_race_try.rb
#
# frozen_string_literal: true

# Regression tryouts for the immortal-receipt resurrection bug (#3625).
#
# Receipt state transitions (revealed!, orphaned!, burned!, expired!) persist
# via `save update_expiration: false` so that advancing state never resets a
# receipt's original expiration. But `save` issues an unconditional HMSET, and
# HMSET on a MISSING key CREATES it. If the receipt's Redis key was TTL-evicted
# between the time an instance was loaded and the time a transition runs, the
# in-memory `state?(:new)` fast-path still passed and the old save recreated the
# hash with NO TTL -- an immortal receipt, re-registered in the instances index.
#
# The transitions now gate on an atomic compare-and-set on the persisted `state`
# field (the shared state_cas feature's #compare_and_set_state!). It FAILS
# CLOSED: a missing
# key's HGET matches nothing so the claim loses and nothing is recreated; an
# already-advanced state also loses so a terminal receipt is never reverted. The
# winner's HSET lands on the live key, preserving its TTL.
#
# These tryouts reproduce the eviction window (DEL the key while an in-memory
# instance still believes it is :new) and assert the fail-closed outcome.

require_relative '../../support/test_models'

OT.boot! :test, true

## A fresh receipt has a positive TTL.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
receipt.dbclient.ttl(receipt.dbkey).positive?
#=> true

## revealed! on a TTL-evicted key does NOT resurrect it (no immortal receipt).
## The loaded instance still believes state?(:new), so the old unconditional
## save would have recreated a TTL-less hash; the CAS makes it fail closed.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
receipt.dbclient.del(receipt.dbkey)          # simulate TTL eviction
result = receipt.revealed!
[!!result, receipt.dbclient.exists(receipt.dbkey), receipt.dbclient.ttl(receipt.dbkey)]
#=> [false, 0, -2]

## burned! on a TTL-evicted key also fails closed.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
receipt.dbclient.del(receipt.dbkey)
result = receipt.burned!
[!!result, receipt.dbclient.exists(receipt.dbkey)]
#=> [false, 0]

## orphaned! on a TTL-evicted key also fails closed.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
receipt.dbclient.del(receipt.dbkey)
result = receipt.orphaned!
[!!result, receipt.dbclient.exists(receipt.dbkey)]
#=> [false, 0]

## A live revealed! still works: returns true, persists state=revealed, clears
## the secret_identifier, and PRESERVES the original TTL (never resets it).
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
before_ttl = receipt.dbclient.ttl(receipt.dbkey)
won        = receipt.revealed!
reloaded   = Onetime::Receipt.load(receipt.objid)
after_ttl  = receipt.dbclient.ttl(receipt.dbkey)
[won, reloaded.state.to_s, reloaded.secret_identifier.to_s.empty?, after_ttl.positive? && after_ttl <= before_ttl]
#=> [true, 'revealed', true, true]

## No state reversion: a stale :new instance loses to an already-advanced
## persisted state, so a terminal receipt is never rolled back.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
stale    = Onetime::Receipt.load(receipt.objid)  # in-memory state is :new
receipt.burned!                                   # another caller advances it
reverted = stale.revealed!                        # stale tries to revert
[!!reverted, Onetime::Receipt.load(receipt.objid).state.to_s]
#=> [false, 'burned']

## True concurrency: many threads race revealed! on separately-loaded instances
## of one receipt. Redis runs the Lua claim atomically, so exactly one wins.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
instances = Array.new(8) { Onetime::Receipt.load(receipt.objid) }
outcomes  = instances.map { |r| Thread.new { r.revealed! } }.map(&:value)
[outcomes.count { |o| o }, Onetime::Receipt.load(receipt.objid).state.to_s]
#=> [1, 'revealed']

## A double revealed! transitions once: the second call loses the CAS (state
## already advanced) and returns falsy without re-firing side effects.
receipt, _secret = Onetime::Receipt.spawn_pair('anon', 3600, 'content')
first  = receipt.revealed!
second = Onetime::Receipt.load(receipt.objid).revealed!
[!!first, !!second]
#=> [true, false]
