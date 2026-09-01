# try/unit/colonel/dry_run_side_effects_try.rb
#
# frozen_string_literal: true

# "A preview writes nothing" — proven, not assumed.
#
# The #4326 PREVIEW EXEMPTION lets every dry_run-capable colonel verb skip the
# confirmation gate (and, once #4327/#4329 land, step-up and the tight rate-limit
# bucket) on its preview path. The entire justification is that a preview has no
# side effects. That was prose in the design doc; this file makes it a test.
#
# For each dry_run class it drives the REAL logic against REAL Redis with NO
# confirmation header and asserts three things:
#
#   1. raise_concerns does not refuse (the exemption works);
#   2. no Redis key is CREATED and the target's own hash is byte-identical
#      (pre-existing keys expiring on their own TTL are ignored — that is the
#      datastore, not us);
#   3. no ColonelAuditEvent is recorded.
#
# NOT covered here: PurgeDlq and ReplayDlq. Their preview path needs a live
# RabbitMQ connection ($rmq_conn) that this container does not have, and their
# adapters refuse with "Message queue is not connected" before reaching the
# guard. Their preview exemption is covered at the unit level in
# apps/api/colonel/spec/logic/colonel/purge_dlq_spec.rb instead.
#
# Run: try --agent try/unit/colonel/dry_run_side_effects_try.rb

require_relative '../../support/test_models'
require 'colonel/logic'

OT.boot! :test

@timestamp = Familia.now.to_i
@db = Familia.dbclient

@colonel = Onetime::Customer.create!(email: "colonel_dryrun_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@target = Onetime::Customer.create!(email: "target_dryrun_#{@timestamp}@example.com")
@target.verified = 'true'
@target.save

@org = Onetime::Organization.create!("DryRun Org #{@timestamp}", @colonel,
  "billing_dryrun_#{@timestamp}@example.com")
@other_org = Onetime::Organization.create!("DryRun Dest #{@timestamp}", @colonel)
@domain = Onetime::CustomDomain.create!("dryrun-#{@timestamp}.example.com", @org.objid)

# No confirmation token anywhere: that is the point. A preview that needed one
# would fail these with Onetime::ConfirmationRequired.
def colonel_strategy
  MockStrategyResult.new(
    session: {}, user: @colonel, auth_method: 'sessionauth', metadata: {},
  )
end

# Everything a preview could touch, in one comparable value.
def snapshot(target_key)
  {
    keys: @db.keys('*').sort,
    target: @db.hgetall(target_key),
    audit: Onetime::ColonelAuditEvent.events.size,
  }
end

# Returns [keys_created, target_changed?, audit_events_written].
# Deletions are ignored: an unrelated key reaching its TTL mid-run is the
# datastore expiring, not this preview writing.
def diff(before, after)
  [
    (after[:keys] - before[:keys]),
    after[:target] != before[:target],
    after[:audit] - before[:audit],
  ]
end

def preview(klass, params, target_key)
  before = snapshot(target_key)
  logic  = klass.new(colonel_strategy, params)
  logic.raise_concerns
  logic.process
  diff(before, snapshot(target_key))
end

## RemoveCustomDomain previews with no confirmation, and writes nothing
preview(
  ColonelAPI::Logic::Colonel::RemoveCustomDomain,
  { 'extid' => @domain.extid },
  @domain.dbkey,
)
#=> [[], false, 0]

## RepairDomain previews with no confirmation, and writes nothing
preview(
  ColonelAPI::Logic::Colonel::RepairDomain,
  { 'extid' => @domain.extid },
  @domain.dbkey,
)
#=> [[], false, 0]

## TransferDomain previews with no confirmation, and writes nothing
preview(
  ColonelAPI::Logic::Colonel::TransferDomain,
  { 'extid' => @domain.extid, 'to_org' => @other_org.extid },
  @domain.dbkey,
)
#=> [[], false, 0]

## ChangeUserEmail previews with no confirmation, and writes nothing
preview(
  ColonelAPI::Logic::Colonel::ChangeUserEmail,
  { 'user_id' => @target.extid, 'new_email' => "moved_#{@timestamp}@example.com" },
  @target.dbkey,
)
#=> [[], false, 0]

## DeleteOrganization previews with no confirmation, and writes nothing
preview(
  ColonelAPI::Logic::Colonel::DeleteOrganization,
  { 'org_id' => @org.extid },
  @org.dbkey,
)
#=> [[], false, 0]

## An APPLY, by contrast, IS gated — the exemption is the preview, not the verb
begin
  logic = ColonelAPI::Logic::Colonel::RemoveCustomDomain.new(
    colonel_strategy, { 'extid' => @domain.extid, 'dry_run' => 'false' },
  )
  logic.raise_concerns
  :not_gated
rescue Onetime::ConfirmationRequired => ex
  ex.to_h[:error_code]
end
#=> "confirmation_required"

## ...and the refused apply still wrote nothing
before = snapshot(@domain.dbkey)
begin
  ColonelAPI::Logic::Colonel::RemoveCustomDomain.new(
    colonel_strategy, { 'extid' => @domain.extid, 'dry_run' => 'false' },
  ).raise_concerns
rescue Onetime::ConfirmationRequired
  nil
end
diff(before, snapshot(@domain.dbkey))
#=> [[], false, 0]

## The confirmed apply DOES go through (the gate is a gate, not a wall)
logic = ColonelAPI::Logic::Colonel::RemoveCustomDomain.new(
  MockStrategyResult.new(
    session: {}, user: @colonel, auth_method: 'sessionauth',
    metadata: { confirm_token: @domain.display_domain },
  ),
  { 'extid' => @domain.extid, 'dry_run' => 'false' },
)
logic.raise_concerns
logic.process[:record][:deleted]
#=> true

# Teardown: the domain is already gone (the apply above removed it).
@org.destroy! if @org.exists?
@other_org.destroy! if @other_org.exists?
@target.destroy! if @target.exists?
@colonel.destroy! if @colonel.exists?
