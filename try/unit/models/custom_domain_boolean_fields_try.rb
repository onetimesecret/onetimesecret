# try/unit/models/custom_domain_boolean_fields_try.rb
#
# frozen_string_literal: true

# CustomDomain's boolean fields (verified, resolving, favicon_fetched) are
# declared `boolean_field ..., storage: :native`, so they hold REAL Ruby
# booleans in memory and persist as the JSON literals true/false.
#
# The bug this covers: these were plain `field` declarations, so whatever a
# caller happened to assign is what got stored — `true` from one path, the
# string 'true' from another. Reads then had to guess, and the ones that
# guessed wrong (`favicon_fetched == true` against a row holding 'true')
# were silent false negatives.
#
# Coverage:
#  1. Write coercion — every input spelling lands as a real boolean
#  2. nil preservation — unset is not the same claim as false
#  3. Persisted bytes — the JSON literal, via both save and the fast writer
#  4. Read healing — legacy rows ('"true"', '1', '"false"') coerce on load
#  5. Downstream — verification_state and safe_dump see booleans

require_relative '../../support/test_models'
require_relative '../../../lib/onetime/jobs/scheduled/favicon_backfill_job'

OT.boot! :test

@now   = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "cd_bool_owner_#{@now}@test.com")
@org   = Onetime::Organization.create!("CD Bool #{@now}", @owner, "cd_bool_#{@now}@test.com")
@domain = Onetime::CustomDomain.create!("cd-bool-#{@now}.example.com", @org.objid)

# ---------------------------------------------------------------------------
# 1. Write coercion — every spelling becomes a real boolean
# ---------------------------------------------------------------------------

## A real boolean stays itself
@domain.verified = true
@domain.verified
#=> true

## The string 'true' coerces
@domain.verified = 'true'
@domain.verified
#=> true

## 'TRUE' is case-insensitive
@domain.verified = 'TRUE'
@domain.verified
#=> true

## Integer 1 coerces
@domain.verified = 1
@domain.verified
#=> true

## 'yes' coerces
@domain.verified = 'yes'
@domain.verified
#=> true

## Anything else is false, not a truthy leftover string
@domain.verified = 'no'
@domain.verified
#=> false

## The string 'false' does NOT read as truthy (the original bug shape)
@domain.resolving = 'false'
@domain.resolving
#=> false

# ---------------------------------------------------------------------------
# 2. nil preservation — unset means "never determined", not false
# ---------------------------------------------------------------------------

## Assigning nil keeps nil rather than coercing to false
@domain.resolving = nil
@domain.resolving
#=> nil

# ---------------------------------------------------------------------------
# 3. Persisted bytes — the JSON literal on both write paths
# ---------------------------------------------------------------------------

## save persists JSON literals, not quoted strings
@domain.verified  = true
@domain.resolving = false
@domain.save
@domain.dbclient.hmget(@domain.dbkey, 'verified', 'resolving')
#=> ['true', 'false']

## A reloaded record reads back real booleans
@reloaded = Onetime::CustomDomain.find_by_identifier(@domain.domainid)
[@reloaded.verified, @reloaded.resolving]
#=> [true, false]

## The fast writer persists the COERCED value, not its raw argument.
## This is the path Familia's setter cannot cover (it hsets
## serialize_value(raw_input)), and the one VerifyDomain uses.
@domain.verified!('yes')
[@domain.verified, @domain.dbclient.hget(@domain.dbkey, 'verified')]
#=> [true, 'true']

## favicon_fetched behaves the same way
@domain.favicon_fetched = true
@domain.save
[@domain.favicon_fetched, @domain.dbclient.hget(@domain.dbkey, 'favicon_fetched')]
#=> [true, 'true']

# ---------------------------------------------------------------------------
# 4. Read healing — legacy rows coerce on load, no data migration
# ---------------------------------------------------------------------------

## A row persisted as a JSON-quoted string heals on load
@domain.dbclient.hset(@domain.dbkey, 'verified', '"true"')
Onetime::CustomDomain.find_by_identifier(@domain.domainid).verified
#=> true

## A row persisted as '1' heals on load
@domain.dbclient.hset(@domain.dbkey, 'verified', '1')
Onetime::CustomDomain.find_by_identifier(@domain.domainid).verified
#=> true

## A row persisted as '"false"' heals on load
@domain.dbclient.hset(@domain.dbkey, 'resolving', '"false"')
Onetime::CustomDomain.find_by_identifier(@domain.domainid).resolving
#=> false

## Unrecognized bytes read as false rather than leaking a truthy string
@domain.dbclient.hset(@domain.dbkey, 'resolving', '"garbage"')
Onetime::CustomDomain.find_by_identifier(@domain.domainid).resolving
#=> false

# ---------------------------------------------------------------------------
# 5. Downstream consumers
# ---------------------------------------------------------------------------

## verification_state reads the fields directly
@domain.txt_validation_value = "abc#{@now}"
@domain.verified  = true
@domain.resolving = true
@domain.verification_state
#=> :verified

## resolving without verified is :resolving
@domain.verified = false
@domain.verification_state
#=> :resolving

## safe_dump emits real JSON booleans
@domain.verified  = true
@domain.resolving = true
@domain.safe_dump.values_at(:verified, :resolving)
#=> [true, true]

## safe_dump collapses an unset field to false for the API contract
@domain.resolving = nil
@domain.safe_dump[:resolving]
#=> false

## The backfill job's "icon already stored" guard sees a legacy row.
## It read `favicon_fetched == true`, so a domain whose row held the string
## rather than the boolean was re-enqueued every night, forever. The guard
## short-circuits, so nothing past it (icon, attempt cap, OT.conf) is read.
@domain.dbclient.hset(@domain.dbkey, 'favicon_fetched', '"true"')
@legacy = Onetime::CustomDomain.find_by_identifier(@domain.domainid)
Onetime::Jobs::Scheduled::FaviconBackfillJob.send(:eligible?, @legacy, Familia.now.to_i)
#=> false

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@domain.destroy!
@org.destroy!
@owner.destroy!
