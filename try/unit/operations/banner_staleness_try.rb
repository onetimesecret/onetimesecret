# try/unit/operations/banner_staleness_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for cross-process banner propagation (TTL-bounded re-read).
#
# A banner published via SetBanner refreshed runtime state ONLY in the process
# that handled the write; every other Puma worker/container served
# `global_banner: nil` until restart. The fix: the `OT.global_banner` /
# `OT.global_banner_scope` accessors call BannerState.refresh_if_stale!, which
# re-reads the Redis pair when the process-local copy is older than
# BannerState::CACHE_TTL (30s). Covers:
# - cross-process publish: direct Redis writes (simulating another process's
#   SetBanner) become visible through OT.global_banner once the cache expires
# - staleness bound: within the TTL the cached value is served (no per-request
#   Redis read)
# - removal: key deletion (another process's ClearBanner) propagates to nil +
#   default scope once the cache expires
# - same-process: SetBanner/ClearBanner remain instantly visible (eager
#   update_features + prime_cache!)
# - fail-soft: a Redis error during refresh serves the last-known value and
#   never raises into the page-render path
#
# NOTE: cache expiry is forced via BannerState.reset_cache! (the test hook) —
# tryouts share one Ruby process, so never rely on the 30s wall clock.
#
# Run: try --agent try/unit/operations/banner_staleness_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/banner'

# Distinct constant names from banner_try.rb: tryout files share one Ruby
# process, so reusing KEY/SCOPE_KEY/DB would emit redefinition warnings.
BSTATE   = Onetime::Operations::BannerState
B_KEY    = BSTATE::KEY
B_SKEY   = BSTATE::SCOPE_KEY
B_CLIENT = Familia.dbclient(BSTATE::DB)

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

# Clean slate: no keys, no cached banner, next accessor read refreshes.
B_CLIENT.del(B_KEY)
B_CLIENT.del(B_SKEY)
Onetime::Runtime.update_features(global_banner: nil, global_banner_scope: BSTATE::DEFAULT_SCOPE)
BSTATE.reset_cache!

# ---- (a) cross-process publish -----------------------------------------

## with no banner anywhere, the accessor serves nil + default scope
[OT.global_banner, OT.global_banner_scope]
#=> [nil, "no_recipient"]

## a direct Redis write (another process's SetBanner) + forced cache expiry
## becomes visible through the accessor pair
B_CLIENT.set(B_KEY, '<b>maintenance window</b>')
B_CLIENT.set(B_SKEY, 'all')
BSTATE.reset_cache!
[OT.global_banner, OT.global_banner_scope]
#=> ["<b>maintenance window</b>", "all"]

## the refresh landed in the runtime Features snapshot (what the serializer reads)
[Onetime::Runtime.features.global_banner, Onetime::Runtime.features.global_banner_scope]
#=> ["<b>maintenance window</b>", "all"]

# ---- (b) staleness bound: no per-request Redis read --------------------

## within the TTL a direct Redis change is NOT picked up (cached value served)
B_CLIENT.set(B_KEY, 'newer content the cache must not see yet')
OT.global_banner
#=> "<b>maintenance window</b>"

## nil is a valid cached state too: deleting the keys without expiring the
## cache still serves the last-known banner (no perpetual cache miss on nil)
B_CLIENT.del(B_KEY)
B_CLIENT.del(B_SKEY)
OT.global_banner
#=> "<b>maintenance window</b>"

# ---- (c) removal propagates --------------------------------------------

## once the cache expires, the deleted keys map to nil + default scope
## (another process's ClearBanner propagates, not just SetBanner)
BSTATE.reset_cache!
[OT.global_banner, OT.global_banner_scope]
#=> [nil, "no_recipient"]

# ---- (d) same-process writes are instant -------------------------------

## SetBanner is visible through the accessor immediately (no expiry needed)
Onetime::Operations::SetBanner.new(content: 'fresh publish', actor: @actor, scope: 'workspace').call
[OT.global_banner, OT.global_banner_scope]
#=> ["fresh publish", "workspace"]

## SetBanner primed the clock: a direct Redis change right after it is NOT
## re-read (the publishing process serves its own write for the TTL window)
B_CLIENT.set(B_KEY, 'other process scribble')
OT.global_banner
#=> "fresh publish"

## ClearBanner is likewise instant in its own process
Onetime::Operations::ClearBanner.new(actor: @actor).call
[OT.global_banner, OT.global_banner_scope]
#=> [nil, "no_recipient"]

# ---- fail-soft: Redis errors never reach the page render ---------------

## a refresh hitting a dead Redis logs, serves the last-known value, and the
## stamped clock prevents a retry stampede (next attempt only after the TTL)
Onetime::Operations::SetBanner.new(content: 'survivor', actor: @actor).call
BSTATE.reset_cache!
@original_dbclient = Familia.method(:dbclient)
Familia.define_singleton_method(:dbclient) { |*_| raise 'redis down' }
begin
  @survived = OT.global_banner
ensure
  Familia.define_singleton_method(:dbclient, @original_dbclient)
end
@survived
#=> "survivor"

## the failed refresh stamped the clock: the next read serves the cache
## without re-attempting Redis (no per-request retries against a dead store)
OT.global_banner
#=> "survivor"

# Cleanup: shared-process hygiene for whatever tryout runs next.
B_CLIENT.del(B_KEY)
B_CLIENT.del(B_SKEY)
Onetime::AdminAuditEvent.events.clear
Onetime::Runtime.update_features(global_banner: nil, global_banner_scope: BSTATE::DEFAULT_SCOPE)
BSTATE.reset_cache!
