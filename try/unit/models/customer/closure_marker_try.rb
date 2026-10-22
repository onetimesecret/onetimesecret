# try/unit/models/customer/closure_marker_try.rb
#
# frozen_string_literal: true

# Customer#mark_closure_started! and #clear_closure_marker! (#4819, #4830).
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
