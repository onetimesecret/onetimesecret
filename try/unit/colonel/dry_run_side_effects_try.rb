# try/unit/colonel/dry_run_side_effects_try.rb
#
# frozen_string_literal: true

# "A preview mutates nothing" — proven, not assumed.
#
# The #4326 PREVIEW EXEMPTION lets every dry_run-capable colonel verb skip the
# confirmation gate (and, once #4327/#4329 land, step-up and the tight rate-limit
# bucket) on its preview path. The entire justification is that a preview has no
# side effects ON ITS TARGET. That was prose in the design doc; this file makes
# it a test.
#
# One deliberate carve-out: #4337 records every dry-run preview as an
# OBSERVATION (`result: preview`) on the budgeted access trail — a preview of a
# destructive verb is reconnaissance, and invisible reconnaissance is the gap
# that epic closed. So the access-events stream is the ONE write a preview is
# allowed (and required) to make; the target and the operator trail stay
# untouched, which is what justifies the exemption.
#
# For each dry_run class it drives the REAL logic against REAL Redis with NO
# confirmation header and asserts four things:
#
#   1. raise_concerns does not refuse (the exemption works);
#   2. no Redis key is CREATED — save the access-events stream itself, which
#      the first observation ever recorded brings into being — and the
#      target's own hash is byte-identical (pre-existing keys expiring on
#      their own TTL are ignored — that is the datastore, not us);
#   3. no OPERATOR-TRAIL ColonelAuditEvent is recorded;
#   4. the access-trail observations written are exactly what #4337 promises:
#      one per PLANNED preview, none when the op never reaches its dry-run
#      branch (a no-issues repair, a guardrail-refused delete).
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

# The one key a preview may create: its own observation stream (#4337).
@access_stream_key = Onetime::ColonelAuditEvent.access_events.dbkey

# Everything a preview could touch, in one comparable value.
def snapshot(target_key)
  {
    keys: @db.keys('*').sort - [@access_stream_key],
    target: @db.hgetall(target_key),
    audit: Onetime::ColonelAuditEvent.events.size,
    access: Onetime::ColonelAuditEvent.access_events.element_count,
  }
end

# Returns [keys_created, target_changed?, audit_events_written,
# observations_written]. Deletions are ignored: an unrelated key reaching its
# TTL mid-run is the datastore expiring, not this preview writing.
def diff(before, after)
  [
    (after[:keys] - before[:keys]),
    after[:target] != before[:target],
    after[:audit] - before[:audit],
    after[:access] - before[:access],
  ]
end

def preview(klass, params, target_key)
  before = snapshot(target_key)
  logic  = klass.new(colonel_strategy, params)
  logic.raise_concerns
  logic.process
  diff(before, snapshot(target_key))
end

## RemoveCustomDomain previews with no confirmation, mutating nothing — one observation
preview(
  ColonelAPI::Logic::Colonel::RemoveCustomDomain,
  { 'extid' => @domain.extid },
  @domain.dbkey,
)
#=> [[], false, 0, 1]

## RepairDomain previews a HEALTHY domain with no confirmation, writing nothing
## at all: the op's no-issues path returns before the dry-run branch, so this
## preview does not even record a #4337 observation — there was nothing to see.
preview(
  ColonelAPI::Logic::Colonel::RepairDomain,
  { 'extid' => @domain.extid },
  @domain.dbkey,
)
#=> [[], false, 0, 0]

## TransferDomain previews with no confirmation, mutating nothing — one observation
preview(
  ColonelAPI::Logic::Colonel::TransferDomain,
  { 'extid' => @domain.extid, 'to_org' => @other_org.extid },
  @domain.dbkey,
)
#=> [[], false, 0, 1]

## ChangeUserEmail previews with no confirmation, mutating nothing — one observation
preview(
  ColonelAPI::Logic::Colonel::ChangeUserEmail,
  { 'user_id' => @target.extid, 'new_email' => "moved_#{@timestamp}@example.com" },
  @target.dbkey,
)
#=> [[], false, 0, 1]

## DeleteOrganization previews with no confirmation and writes nothing at all:
## @org still owns @domain, so the op's has-domains guardrail refuses ahead of
## the dry-run branch — a refused preview records no #4337 observation either
## (auditing refusals would be a log-eviction primitive; see the op).
preview(
  ColonelAPI::Logic::Colonel::DeleteOrganization,
  { 'org_id' => @org.extid },
  @org.dbkey,
)
#=> [[], false, 0, 0]

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

## ...and the refused apply still wrote nothing — not even an observation:
## the refusal happens in raise_concerns, before the op (and its #4337
## preview record) is ever reached
before = snapshot(@domain.dbkey)
begin
  ColonelAPI::Logic::Colonel::RemoveCustomDomain.new(
    colonel_strategy, { 'extid' => @domain.extid, 'dry_run' => 'false' },
  ).raise_concerns
rescue Onetime::ConfirmationRequired
  nil
end
diff(before, snapshot(@domain.dbkey))
#=> [[], false, 0, 0]

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
