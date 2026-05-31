# frozen_string_literal: true

# Org entitlement/limit materialization — pull-vs-materialize discrimination
#
# Reproduces the reported symptom ("limits not updating after catalog
# push/pull") and proves whether the cause is:
#   (A) the pull→materialize decoupling (workflow gap), or
#   (B) a real write/read bug in materialize_entitlements_from_plan / limit_for.
#
# Sequence mirrors the operator flow:
#   1. seed plan (teams.max=5), create org, materialize  -> limit 5
#   2. mutate cached plan (teams.max=10) WITHOUT re-materializing (== pull) -> still 5
#   3. run the real materialize step                       -> 10 iff write path OK

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/lib/test_support/billing_helpers'
require_relative '../../../apps/web/billing/operations/apply_subscription_to_org'

PLAN_ID = 'limit_mat_test_v1'

def seed_plan(teams_max)
  BillingTestHelpers.populate_test_plans([
    {
      plan_id: PLAN_ID,
      name: 'Limit Mat Test',
      tier: 'multi_team',
      entitlements: %w[create_secrets custom_domains],
      limits: { 'teams.max' => teams_max },
    },
  ])
end

def make_org
  owner = Onetime::Customer.create!("limit-mat-#{Familia.now.to_i}@example.com")
  org   = Onetime::Organization.create!('Limit Mat Org', owner)
  org.planid = PLAN_ID
  org.save
  [org, owner]
end

## Setup: billing enabled, plan seeded with teams.max=5, org materialized
BillingTestHelpers.restore_billing!(enabled: true)
seed_plan(5)
@org, @owner = make_org
@plan_at_materialize = ::Billing::Plan.load(PLAN_ID)
@ents_at_materialize = @plan_at_materialize.entitlements.to_a.sort
@time_before_materialize = Familia.now.to_i
@org.materialize_entitlements_from_plan(@plan_at_materialize)
@time_after_materialize = Familia.now.to_i
@org.limit_for('teams')
#=> 5

## Verify plan entitlements at materialization time
@ents_at_materialize
#=> ["create_secrets", "custom_domains"]

## Verify org's entitlements_plan immediately after materialization
@org.entitlements_plan.to_a.sort
#=> ["create_secrets", "custom_domains"]

## DEBUG: plan entitlements after materialize (should match @ents_at_materialize)
@plan_at_materialize.entitlements.to_a.sort
#=> ["create_secrets", "custom_domains"]

## DEBUG: materialization timestamp is from our call (not stale)
@parsed = @org.send(:materialized_entitlements_at_parsed)
@mat_timestamp = @parsed[:timestamp]
@mat_timestamp >= @time_before_materialize && @mat_timestamp <= @time_after_materialize
#=> true

## DEBUG: org objid exists and is non-empty
@org.objid.to_s.length > 10
#=> true

## DEBUG: org's Redis key contains identifier
@org.dbkey.include?(@org.objid)
#=> true

## DEBUG: re-read org from Redis shows same hash
@org_reloaded = Onetime::Organization.load(@org.objid)
@org_reloaded.materialized_entitlements_at == @org.materialized_entitlements_at
#=> true

## DEBUG: stored hash value
@stored_hash = @org.send(:materialized_entitlements_at_parsed)&.dig(:content_hash).to_s
@stored_hash.length
#=> 12

## DEBUG: expected hash for known entitlements + limits
# snapshot_content_hash includes limits, not just entitlements
@expected_hash = Onetime::Organization.snapshot_content_hash(
  ["create_secrets", "custom_domains"],
  { "teams.max" => "5" }
)
@expected_hash
#=> "0b0053014180"

## DEBUG: hashes match (CORE ASSERTION)
[@stored_hash, @expected_hash]
#=> [@expected_hash, @expected_hash]

## DEBUG: plan.entitlements Redis key contains plan_id
@plan_at_materialize.entitlements.dbkey.include?(PLAN_ID)
#=> true

## DEBUG: plan entitlements count from raw Redis
@plan_at_materialize.entitlements.size
#=> 2

## DEBUG: check if org existed before this test (materialized_entitlements_at should be fresh)
@fresh_org = Onetime::Organization.load(@org.objid)
@fresh_parsed = @fresh_org.send(:materialized_entitlements_at_parsed)
@fresh_parsed[:timestamp] >= @time_before_materialize
#=> true

## Org reports it is materialized
@org.entitlements_materialized?
#=> true

## Materialized limits are read from org-local limits_plan (not the live plan)
@org.materialized_limit_for('teams.max')
#=> 5

## STEP 2 (== catalog pull): mutate cached plan limits, entitlements unchanged
## No re-materialization happens here — this is exactly what `catalog pull` does.
plan = ::Billing::Plan.load(PLAN_ID)
plan.limits['teams.max'] = '10'
plan.save
::Billing::Plan.load(PLAN_ID).limits['teams.max']
#=> "10"

## SYMPTOM REPRODUCED: org limit still 5 after pull (org-local copy is stale)
@org.limit_for('teams')
#=> 5

## DEBUG: plan entitlements values (sorted)
@debug_plan = ::Billing::Plan.load(PLAN_ID)
@debug_plan.entitlements.to_a.sort
#=> ["create_secrets", "custom_domains"]

## DEBUG: org entitlements values (sorted)
@org.entitlements_plan.to_a.sort
#=> ["create_secrets", "custom_domains"]

## DEBUG: entitlements arrays match
@debug_plan = ::Billing::Plan.load(PLAN_ID)
@debug_plan.entitlements.to_a.sort == @org.entitlements_plan.to_a.sort
#=> true

## DEBUG: hashes differ after plan mutation (org still has old limits hash)
@debug_plan = ::Billing::Plan.load(PLAN_ID)
@debug_plan_ents = @debug_plan.entitlements.to_a.sort
@debug_plan_limits = @debug_plan.limits.hgetall  # now teams.max=10
@debug_parsed = @org.send(:materialized_entitlements_at_parsed)
@debug_org_hash = @debug_parsed ? @debug_parsed[:content_hash] : 'PARSED_NIL'  # still from teams.max=5
@debug_plan_hash = Onetime::Organization.snapshot_content_hash(@debug_plan_ents, @debug_plan_limits)
@debug_org_hash != @debug_plan_hash  # hashes should DIFFER after plan change
#=> true

## Staleness check correctly detects limits change (hash includes limits now)
@debug_plan = ::Billing::Plan.load(PLAN_ID)
@org.entitlements_stale?(@debug_plan)
#=> true

## STEP 3: run the real materialize step (what `billing plans materialize` does)
result = Billing::Operations::ApplySubscriptionToOrg.materialize_entitlements_for_org(@org)
result.status
#=> :materialized

## After materialize, the org-local limit reflects the new plan value
@org.limit_for('teams')
#=> 10

## Re-loaded org also reflects it (persisted, not just in-memory)
Onetime::Organization.load(@org.objid).limit_for('teams')
#=> 10

## Teardown
@org.destroy!
@owner.destroy!
BillingTestHelpers.cleanup_billing_state!
true
#=> true
