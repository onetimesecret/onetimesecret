# try/unit/models/customer/closure_marker_try.rb
#
# frozen_string_literal: true

# Customer#mark_closure_started!, #clear_closure_marker! and
# Customer.closure_state (#4819, #4830).
#
# The marker is written only while the record exists, and only once: a
# closure that resumes keeps the time the first one started, and a write
# racing a deletion must not recreate the record as a one-field hash.
#
# Run: bundle exec try try/unit/models/customer/closure_marker_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test, false

@test_id = SecureRandom.hex(6)
@cust    = Onetime::Customer.create!(email: "closure_marker_#{@test_id}@example.com")

# TRYOUTS

## A new record is not closing
Onetime::Customer.load(@cust.objid).closing?
#=> false

## Marking a live record writes the marker and reports the write
@cust.mark_closure_started!(at: 1_700_000_000)
#=> :written

## The in-memory value matches what was stored
[@cust.closing?, @cust.closure_started_at]
#=> [true, 1_700_000_000]

## A reload sees the marker
Onetime::Customer.load(@cust.objid).closure_started_at
#=> 1_700_000_000

## A second mark keeps the first timestamp, in memory and stored, and says so
outcome = @cust.mark_closure_started!(at: 1_800_000_000)
[outcome, @cust.closure_started_at, Onetime::Customer.load(@cust.objid).closure_started_at]
#=> [:kept, 1_700_000_000, 1_700_000_000]

## A stale in-memory copy picks up the stored timestamp
stale = Onetime::Customer.load(@cust.objid)
stale.closure_started_at = nil
stale.mark_closure_started!(at: 1_900_000_000)
stale.closure_started_at
#=> 1_700_000_000

## Clearing removes the stored field
@cust.clear_closure_marker!
[@cust.closing?, Onetime::Customer.load(@cust.objid).closing?]
#=> [false, false]

## Marking a deleted record writes nothing and reports nil
@gone_key = @cust.dbkey
@cust.destroy!
@cust.mark_closure_started!(at: 1_700_000_000)
#=> nil

## The deleted record's key was not recreated
Familia.dbclient.exists(@gone_key)
#=> 0

## Clearing a deleted record does not recreate it either
@cust.clear_closure_marker!
Familia.dbclient.exists(@gone_key)
#=> 0

## closure_state: nil for a record no closure has touched
Onetime::Customer.closure_state(nil, open_auth_account: false)
#=> nil

## closure_state: a marker younger than CLOSURE_STALE_AFTER is in progress, whatever the account reads
now = 1_800_000_000
[true, false, nil].map { |open| Onetime::Customer.closure_state(now - 60, open_auth_account: open, now: now) }
#=> [:in_progress, :in_progress, :in_progress]

## closure_state: from CLOSURE_STALE_AFTER on, a live account of its own means rolled back, none means interrupted
now   = 1_800_000_000
stale = now - Onetime::Customer::CLOSURE_STALE_AFTER
[true, false].map { |open| Onetime::Customer.closure_state(stale, open_auth_account: open, now: now) }
#=> [:rolled_back, :interrupted]

## closure_state: an old marker with an unreadable account decides nothing
now = 1_800_000_000
Onetime::Customer.closure_state(now - Onetime::Customer::CLOSURE_STALE_AFTER, open_auth_account: nil, now: now)
#=> nil

## The instance form classifies the record's own marker
record = Onetime::Customer.new(email: "closure_state_#{@test_id}@example.com", closure_started_at: 1_700_000_000)
[record.closure_state(open_auth_account: false, now: 1_800_000_000),
 Onetime::Customer.new(email: "unmarked_#{@test_id}@example.com").closure_state(open_auth_account: false)]
#=> [:interrupted, nil]
