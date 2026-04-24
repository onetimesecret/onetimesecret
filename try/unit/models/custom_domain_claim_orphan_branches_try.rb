# try/unit/models/custom_domain_claim_orphan_branches_try.rb
#
# frozen_string_literal: true

# Covers the non-happy-path branches of CustomDomain.claim_orphaned_domain
# plus the load-bearing guard_unique_display_domain_index! self-reference
# assertion that makes atomic_write safe for orphan claims.
#
# Branches under test:
#   - Same-org re-claim: idempotent short-circuit when stored org_id matches
#   - Claimed-by-another-org: raise when stored org_id differs
#   - atomic_write single-MULTI atomicity across locations C, D, E
#   - guard_unique_display_domain_index! self-reference does not raise
#   - WATCH-abort branch (documented gap; simulation noted below)

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for claim_orphan branch tests"

@ts      = Familia.now.to_i
@owner_a = Onetime::Customer.create!(email: "claim_branch_a_#{@ts}@test.com")
@owner_b = Onetime::Customer.create!(email: "claim_branch_b_#{@ts}@test.com")
@org_a   = Onetime::Organization.create!("Org A #{@ts}", @owner_a, "claim-branch-a-#{@ts}@test.com")
@org_b   = Onetime::Organization.create!("Org B #{@ts}", @owner_b, "claim-branch-b-#{@ts}@test.com")

# Helper: orphan a freshly-created domain by clearing org_id + org zset + owners.
# Leaves display_domain and display_domains/display_domain_index intact, which
# is the exact state claim_orphaned_domain expects.
def orphan!(domain, owning_org)
  owning_org.remove_domain(domain)
  Familia.dbclient.hdel(domain.dbkey, 'org_id')
  Onetime::CustomDomain.owners.remove(domain.to_s)
  Onetime::CustomDomain.load_by_display_domain(domain.display_domain)
end

## Raw hget() returns the Familia v2 JSON-encoded form (e.g. `"\"<uuid>\""`),
## while the field accessor returns the bare value. claim_orphaned_domain
## now JSON.parse()s the hget value so the same-org idempotent branch
## actually matches. The encoding gap is documented here as a regression
## indicator — if Familia ever stops wrapping scalars, the second element
## of the comparison goes away and the first element becomes `true`.
@probe_domain = Onetime::CustomDomain.create!("probe-#{@ts}.example.com", @org_a.objid)
@probe_hget   = @probe_domain.hget(:org_id)
@probe_field  = @probe_domain.org_id
[@probe_hget.to_s == @probe_field.to_s, @probe_hget.to_s.include?(@probe_field.to_s)]
#=> [false, true]

## Branch: same-org idempotent short-circuit returns the existing record
## without raising. claim_orphaned_domain sees a non-empty hget value,
## JSON.parse()s it, confirms it matches org_id, and returns early.
@idempotent_domain = Onetime::CustomDomain.create!("idempotent-#{@ts}.example.com", @org_a.objid)
@idempotent_result = Onetime::CustomDomain.claim_orphaned_domain(@idempotent_domain, @org_a.objid)
@idempotent_result.identifier == @idempotent_domain.identifier
#=> true

## Re-claiming leaves the record intact — no side-effect rewrites
@idempotent_domain_refetched = Onetime::CustomDomain.find_by_identifier(@idempotent_domain.identifier)
@idempotent_domain_refetched.org_id == @org_a.objid
#=> true

## Branch: already-claimed-by-another-org raises.
## (Exercises line 818 fall-through after line 813 fails to short-circuit.)
@conflict_domain = Onetime::CustomDomain.create!("conflict-#{@ts}.example.com", @org_a.objid)
begin
  Onetime::CustomDomain.claim_orphaned_domain(@conflict_domain, @org_b.objid)
  :no_raise
rescue Onetime::Problem => ex
  ex.message
end
#=> 'Domain is registered to another organization'

## Branch: atomic_write single-MULTI atomicity across all three locations.
## Set up an orphan, claim it, and verify *all* of C/D/E reflect the claim.
## In the pre-fix world the claim_orphaned_domain call made `save` run
## inside a raw dbclient.multi, so guard_unique_display_domain_index! saw
## a QUEUED future instead of the real existing_id -- the atomicity was
## the regression target.
@atomic_domain_name = "atomicity-#{@ts}.example.com"
@atomic_domain      = Onetime::CustomDomain.create!(@atomic_domain_name, @org_a.objid)
orphan!(@atomic_domain, @org_a)
Onetime::CustomDomain.orphaned?(@atomic_domain_name)
#=> true

## Claim-for-org_b via create!
@claimed_atomic = Onetime::CustomDomain.create!(@atomic_domain_name, @org_b.objid)
@claimed_atomic.display_domain
#=> @atomic_domain_name

## Location D (object hash org_id field)
@claimed_atomic.org_id == @org_b.objid
#=> true

## Location C (organization.domains sorted set) -- fresh-load org to bypass caches
@org_b_reloaded = Onetime::Organization.load(@org_b.objid)
@org_b_reloaded.domain?(@claimed_atomic)
#=> true

## Prior owner (org_a) no longer carries the domain in its zset
@org_a_reloaded = Onetime::Organization.load(@org_a.objid)
@org_a_reloaded.domain?(@claimed_atomic)
#=> false

## Location E (global owners hash) matches new org
Onetime::CustomDomain.owners.get(@claimed_atomic.to_s) == @org_b.objid
#=> true

## guard_unique_display_domain_index! self-reference safety.
## During orphan claim, the display_domain_index still points at this
## domain's identifier. The guard must treat `existing_id == identifier`
## as a pass (not raise RecordExistsError). Re-run the guard directly
## against the already-claimed record to confirm.
@claimed_atomic.send(:guard_unique_display_domain_index!)
#=> nil

## display_domains (manual) still maps to the same identifier after claim
Onetime::CustomDomain.display_domains.get(@atomic_domain_name) == @claimed_atomic.identifier
#=> true

## display_domain_index (auto) still maps to the same identifier after claim
Onetime::CustomDomain.display_domain_index.get(@atomic_domain_name) == @claimed_atomic.identifier
#=> true

# Branch documentation: WATCH-abort path (result == false || result.nil?).
# Simulating a real WATCH race inside a tryout requires a second connection
# mutating existing.dbkey between WATCH and MULTI -- feasible with a raw
# Redis client, but fragile because Familia's atomic_write opens its own
# connection pooling. The guard-clause in claim_orphaned_domain matches
# atomic_write's documented contract:
#   - atomic_write returns false if the transaction is discarded
#     (atomic_write.rb:190-195, via atomic_write_success?(nil) => false).
#   - claim_orphaned_domain treats both `false` and `nil` as failure.

# Teardown
@claimed_atomic.destroy! if @claimed_atomic&.exists?
@conflict_domain.destroy! if @conflict_domain&.exists?
@idempotent_domain.destroy! if @idempotent_domain&.exists?
@probe_domain.destroy! if @probe_domain&.exists?
@org_a.destroy! if @org_a&.exists?
@org_b.destroy! if @org_b&.exists?
@owner_a.destroy! if @owner_a&.exists?
@owner_b.destroy! if @owner_b&.exists?
