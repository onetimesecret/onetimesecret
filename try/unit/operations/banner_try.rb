# try/unit/operations/banner_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted broadcast-banner operations (epic #41):
#   Onetime::Operations::GetBanner / SetBanner / ClearBanner
#
# These are the SINGLE implementation of the banner get/set/clear verbs (the
# colonel API + `bin/ots banner` CLI are thin adapters). Covers:
# - GetBanner on an empty store: active=false, content nil, READ-ONLY (no audit)
# - SetBanner: writes the raw content, refreshes runtime, returns :success,
#   records EXACTLY ONE audit event (verb banner.set, actor = PUBLIC id)
# - GetBanner after set: reflects content + active, ttl nil for a persistent banner
# - SetBanner with ttl: stores with an expiry that GetBanner reports (>0)
# - Behavioural parity: the stored value is byte-identical to a direct db.set
# - SetBanner empty content: raises ArgumentError, writes nothing, NO audit
# - ClearBanner: deletes, refreshes runtime, returns :success, one audit event
# - ClearBanner idempotency: clearing an unset banner is :not_set with NO audit
#
# Run: try --agent try/unit/operations/banner_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/banner'

AE  = Onetime::AdminAuditEvent
KEY = Onetime::Operations::BannerState::KEY
DB  = Familia.dbclient(Onetime::Operations::BannerState::DB)

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid
@msg   = '<a href="/status">Scheduled maintenance Sun 02:00 UTC</a>'

# Clean slate.
DB.del(KEY)
AE.events.clear

# ---- GetBanner: empty store -------------------------------------------

## GetBanner on an empty store reports inactive with nil content
@g0 = Onetime::Operations::GetBanner.new.call
[@g0.active, @g0.content.nil?, @g0.ttl.nil?]
#=> [false, true, true]

## GetBanner exposes the backing key + database (single source of truth)
[@g0.key, @g0.database]
#=> ["global_banner", 0]

## a read records NO audit event (read-only verb)
AE.count
#=> 0

# ---- SetBanner: publish (persistent) ----------------------------------

## SetBanner returns a :success Result carrying the stored content
@set = Onetime::Operations::SetBanner.new(content: @msg, actor: @actor).call
[@set.status, @set.content, @set.ttl.nil?]
#=> [:success, "<a href=\"/status\">Scheduled maintenance Sun 02:00 UTC</a>", true]

## the content is stored VERBATIM (raw HTML, no sanitising on write — CLI parity)
DB.get(KEY)
#=> "<a href=\"/status\">Scheduled maintenance Sun 02:00 UTC</a>"

## the runtime features state is refreshed to the new banner
Onetime::Runtime.features.global_banner
#=> "<a href=\"/status\">Scheduled maintenance Sun 02:00 UTC</a>"

## exactly ONE audit event was recorded for the publish
AE.count
#=> 1

## the audit event is the set verb, targeting the banner key, actored by PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["banner.set", "global_banner", "ur1colonelpub"]

## GetBanner now reflects the active persistent banner (ttl nil)
@g1 = Onetime::Operations::GetBanner.new.call
[@g1.active, @g1.content, @g1.ttl.nil?]
#=> [true, "<a href=\"/status\">Scheduled maintenance Sun 02:00 UTC</a>", true]

# ---- SetBanner: with TTL ----------------------------------------------

## SetBanner with a ttl stores an expiring banner
AE.events.clear
@set_ttl = Onetime::Operations::SetBanner.new(content: 'temp', actor: @actor, ttl: 3600).call
[@set_ttl.status, @set_ttl.ttl]
#=> [:success, 3600]

## GetBanner reports a positive ttl for the expiring banner
Onetime::Operations::GetBanner.new.call.ttl.positive?
#=> true

## the ttl publish also recorded exactly one audit event
AE.count
#=> 1

# ---- SetBanner: empty content backstop --------------------------------

## SetBanner with empty content raises ArgumentError (defensive backstop)
begin
  Onetime::Operations::SetBanner.new(content: '', actor: @actor).call
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## the failed (empty) set recorded NO audit event
# NOTE: only a truly empty string is rejected — whitespace-only content is stored
# verbatim, matching the CLI's bare-argument path (no strip), which is bit-for-bit
# preserved. HTTP-layer trimming/validation lives in the colonel SetBanner logic.
AE.events.clear
begin
  Onetime::Operations::SetBanner.new(content: '', actor: @actor).call
rescue ArgumentError
  nil
end
AE.count
#=> 0

# ---- Behavioural parity: stored value byte-identical -------------------

## a value written by the op equals a value written by a direct db.set
DB.del(KEY)
Onetime::Operations::SetBanner.new(content: 'parity-check', actor: @actor).call
@via_op = DB.get(KEY)
DB.del(KEY)
DB.set(KEY, 'parity-check')
@via_direct = DB.get(KEY)
@via_op == @via_direct
#=> true

# ---- ClearBanner: success ---------------------------------------------

## ClearBanner removes the banner and returns :success
AE.events.clear
@clear = Onetime::Operations::ClearBanner.new(actor: @actor).call
[@clear.status, @clear.cleared]
#=> [:success, true]

## the key is gone and the runtime state is refreshed to nil
[DB.get(KEY).nil?, Onetime::Runtime.features.global_banner.nil?]
#=> [true, true]

## exactly ONE audit event was recorded for the clear
AE.count
#=> 1

## the audit event is the clear verb targeting the banner key
@cev = AE.recent(1).first
[@cev['verb'], @cev['target'], @cev['actor']]
#=> ["banner.clear", "global_banner", "ur1colonelpub"]

# ---- ClearBanner: idempotent no-op ------------------------------------

## clearing an already-cleared banner is a no-op (:not_set)
AE.events.clear
@noop = Onetime::Operations::ClearBanner.new(actor: @actor).call
[@noop.status, @noop.cleared]
#=> [:not_set, false]

## a no-op clear records NO audit event (nothing mutated)
AE.count
#=> 0

# Cleanup
DB.del(KEY)
AE.events.clear
Onetime::Runtime.update_features(global_banner: nil)
