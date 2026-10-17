# try/unit/operations/domain_toolbox_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted domain-toolbox operations (epic #43):
#   Onetime::Operations::Domains::{Probe, OrphanedScan, Repair, Transfer}
#
# These are the SINGLE implementation of the toolbox verbs (the `bin/ots domains
# {probe,orphaned,repair,transfer}` CLI + the colonel endpoints are thin
# adapters). Covers, per CONTRACT 4:
# - READ-ONLY ops (Probe, OrphanedScan) record NO audit events.
# - Repair/Transfer dry-run: compute a plan, mutate NOTHING, audit NOTHING.
# - Repair/Transfer apply: mutate + record EXACTLY ONE audit event.
# - Repair no-op (no issues) records no audit event.
# - Repair :needs_org and Transfer :mismatch are REFUSED privileged mutations:
#   they mutate nothing but each record ONE result: :failure event, same verb
#   and target as a success. A refusal that returns a Result must be as
#   traceable as one that raises.
# - A Transfer that blows up mid-apply records ONE result: :failure event via
#   Onetime::AuditedFailure and re-raises (the success-path record never runs).
# - Repair --org-id and Transfer of an ORPHANED domain adopt it through
#   CustomDomain.claim_orphaned_domain: the canonical-name entry is taken, the
#   ownership verification is reset, the TXT value is new, and the kept
#   per-domain state is reported.
#
# Run: try --agent try/unit/operations/domain_toolbox_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/domains/probe'
require 'onetime/operations/domains/orphaned_scan'
require 'onetime/operations/domains/repair'
require 'onetime/operations/domains/transfer'

AE = Onetime::ColonelAuditEvent

@actor = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid

@test_id = SecureRandom.hex(4)
@cust1   = Onetime::Customer.create!(email: "dtcust1_#{@test_id}@example.com")
@cust2   = Onetime::Customer.create!(email: "dtcust2_#{@test_id}@example.com")
@org1    = Onetime::Organization.create!("DT Org 1 #{@test_id}", @cust1, "billing+dt1+#{@test_id}@onetimesecret.com")
@org2    = Onetime::Organization.create!("DT Org 2 #{@test_id}", @cust2, "billing+dt2+#{@test_id}@onetimesecret.com")

AE.events.clear

# ---- Probe: read-only, no audit ---------------------------------------

## Probe returns a result Hash with a health classification
@probe = Onetime::Operations::Domains::Probe.new(
  hostname: "no-such-host-#{@test_id}.invalid", timeout: 2,
).call
@probe[:health].is_a?(String)
#=> true

## an unresolvable host classifies as a DNS error (fails fast, no network)
@probe[:health]
#=> "dns_error"

## a probe records NO audit event (read-only)
AE.count
#=> 0

# ---- OrphanedScan: read-only, no audit --------------------------------

## an orphaned domain (blank org_id) shows up in the scan
# The model's #save refuses a blank org_id, so an orphaned record (a data-drift
# state) is produced by clearing the field directly in the store, then reloading.
@orphan_seed = Onetime::CustomDomain.create!("dt-orphan-#{@test_id}.example.com", @org1.objid)
Familia.dbclient.hset(@orphan_seed.dbkey, 'org_id', '')
@orphan = Onetime::CustomDomain.find_by_identifier(@orphan_seed.domainid)
@scan = Onetime::Operations::Domains::OrphanedScan.new(per_page: nil).call
@scan.domains.map { |d| d[:domain_id] }.include?(@orphan.domainid)
#=> true

## the orphaned summary carries the public extid + display_domain
@row = @scan.domains.find { |d| d[:domain_id] == @orphan.domainid }
[@row[:extid] == @orphan.extid, @row[:display_domain] == @orphan.display_domain]
#=> [true, true]

## the scan records NO audit event (read-only)
AE.count
#=> 0

# ---- Repair: dry-run computes, mutates/audits nothing -----------------

## a domain with org_id set but missing from the collection is an issue
# parse + save persists the record WITHOUT adding it to the org's domains
# collection (unlike create!), reproducing the not-in-collection drift.
@dom = Onetime::CustomDomain.parse("dt-repair-#{@test_id}.example.com", @org1.org_id)
@dom.save
@in_before = @org1.list_domains.map(&:domainid).include?(@dom.domainid)
@in_before
#=> false

## dry-run finds the not-in-collection issue and plans (no mutation)
@plan = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: true).call
[@plan.status, @plan.issues.size]
#=> [:planned, 1]

## a dry-run records NO audit event
AE.count
#=> 0

## the domain is still NOT in the collection after a dry-run (nothing mutated)
@org1.list_domains.map(&:domainid).include?(@dom.domainid)
#=> false

# ---- Repair: apply mutates + audits exactly once ----------------------

## applying the repair adds the domain to the org collection
@applied = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: false).call
@applied.status
#=> :repaired

## the domain is now in the org's collection (model actually mutated)
@org1.list_domains.map(&:domainid).include?(@dom.domainid)
#=> true

## exactly ONE audit event was recorded for the repair
AE.count
#=> 1

## the audit event is the repair verb, targeting the domain extid, public actor
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["domain.repair", @dom.extid, "ur1colonelpub"]

# ---- Repair: no-op (already consistent) records no audit --------------

## re-running repair on the now-consistent domain finds no issues
AE.events.clear
@noop = Onetime::Operations::Domains::Repair.new(domain: @dom, actor: @actor, dry_run: false).call
@noop.status
#=> :no_issues

## a no-issue repair records NO audit event
AE.count
#=> 0

# ---- Repair: orphaned needs a target org ------------------------------

## an orphaned domain with no target org is blocked (:needs_org)
AE.events.clear
@nblk = Onetime::Operations::Domains::Repair.new(domain: @orphan, actor: @actor, dry_run: false).call
[@nblk.status, AE.count]
#=> [:needs_org, 1]

## the refusal is recorded as a FAILURE on the repair verb, targeting the domain
@nev = AE.recent(1).first
[@nev['verb'], @nev['target'], @nev['result'], @nev['detail']['reason']]
#=> ["domain.repair", @orphan.extid, "failure", "needs_org"]

# ---- Transfer: dry-run computes, mutates/audits nothing ---------------

## set up a domain owned by org1 and present in its collection
@tdom = Onetime::CustomDomain.create!("dt-transfer-#{@test_id}.example.com", @org1.objid)
@org1.add_domain(@tdom)
AE.events.clear
@tplan = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org2, actor: @actor, dry_run: true,
).call
[@tplan.status, @tplan.to_org_id == @org2.org_id]
#=> [:planned, true]

## a dry-run transfer records NO audit and leaves ownership unchanged
[AE.count, @tdom.org_id == @org1.org_id]
#=> [0, true]

# ---- Transfer: apply mutates + audits exactly once --------------------

## applying the transfer moves the domain to org2
@tapplied = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org2, actor: @actor, dry_run: false,
).call
@tapplied.status
#=> :transferred

## the domain now belongs to org2 (org_id updated)
reloaded = Onetime::CustomDomain.load_by_display_domain(@tdom.display_domain)
reloaded.org_id == @org2.org_id
#=> true

## the domain is in org2's collection and gone from org1's
[@org2.list_domains.map(&:domainid).include?(@tdom.domainid),
 @org1.list_domains.map(&:domainid).include?(@tdom.domainid)]
#=> [true, false]

## the CustomDomain.owners index followed the transfer
# owners is a second, independently-maintained ownership index that
# Organization#unlisted_owned_domains reads as the org-deletion drift guard.
# Left on the source org it made that org PERMANENTLY undeletable.
Onetime::CustomDomain.owners.get(@tdom.domainid)
#=> @org2.objid

## the source org is left with NO drifted owned domains
@org1.unlisted_owned_domains.map(&:display_domain)
#=> []

## exactly ONE audit event was recorded for the transfer
AE.count
#=> 1

## the audit event is the transfer verb targeting the domain extid
@tev = AE.recent(1).first
[@tev['verb'], @tev['target'], @tev['actor']]
#=> ["domain.transfer", @tdom.extid, "ur1colonelpub"]

# ---- Transfer: explicit from_org mismatch is blocked ------------------

## an explicit from_org that isn't the current owner is a :mismatch
AE.events.clear
@mm = Onetime::Operations::Domains::Transfer.new(
  domain: @tdom, to_org: @org1, from_org: @org1, actor: @actor, dry_run: false,
).call
[@mm.status, AE.count]
#=> [:mismatch, 1]

## the refusal is recorded as a FAILURE on the transfer verb, targeting the domain
@mmev = AE.recent(1).first
[@mmev['verb'], @mmev['target'], @mmev['result'], @mmev['detail']['reason']]
#=> ["domain.transfer", @tdom.extid, "failure", "mismatch"]

# ---- Transfer: a raise mid-apply is audited, then re-raised -----------
#
# The Onetime::AuditedFailure mechanism. The success-path record sits AFTER
# the collection add, so without the macro a transfer that rolls back leaves
# no trace at all. A frozen destination org makes add_domain blow up.

## a transfer that raises mid-apply re-raises the original error
AE.events.clear
@boom_org = Onetime::Organization.load(@org1.objid)
@boom_org.define_singleton_method(:add_domain) { |*| raise(Onetime::Problem, 'collection add exploded') }
begin
  Onetime::Operations::Domains::Transfer.new(
    domain: @tdom, to_org: @boom_org, actor: @actor, dry_run: false,
  ).call
  :no_raise
rescue StandardError => ex
  ex.class.to_s
end
#=> "RuntimeError"

## it recorded EXACTLY ONE result: :failure event with the unchanged verb/target
@bev = AE.recent(1).first
[AE.count, @bev['verb'], @bev['target'], @bev['result'], @bev['detail']['dry_run']]
#=> [1, "domain.transfer", @tdom.extid, "failure", false]

## the rollback restored BOTH ownership writes, not just org_id
# A rollback that put org_id back but left owners on the destination is the
# same drift by another route: the pair must stay consistent.
@rb = Onetime::CustomDomain.find_by_identifier(@tdom.domainid)
[@rb.org_id, Onetime::CustomDomain.owners.get(@tdom.domainid)]
#=> [@org2.org_id, @org2.objid]

# ---- Transfer round trip: the source org stays DELETABLE ---------------
#
# The regression in full: transfer a domain away from org A, then delete org A.
# Before owners moved with org_id, Organization#destroy! raised
# 'domain records still reference it' forever, Org::Delete refused with
# :drifted_domains, and neither the colonel path nor `bin/ots org delete` has a
# force override. The advertised remediation (`domains doctor --all --repair`) could
# not help either: doctor check #4 keys off org_id, which is by then correct.

## a source org whose only domain was transferred away has no drift
@cust3 = Onetime::Customer.create!(email: "dtcust3_#{@test_id}@example.com")
@org3  = Onetime::Organization.create!("DT Org 3 #{@test_id}", @cust3, "billing+dt3+#{@test_id}@onetimesecret.com")
@rtdom = Onetime::CustomDomain.create!("dt-roundtrip-#{@test_id}.example.com", @org3.objid)
@org3.add_domain(@rtdom)
Onetime::Operations::Domains::Transfer.new(
  domain: @rtdom, to_org: @org2, actor: @actor, dry_run: false,
).call.status
#=> :transferred

## the source org sees neither a listed nor an unlisted domain
[@org3.domain_count, @org3.unlisted_owned_domains.size]
#=> [0, 0]

## and it can actually be deleted
@org3.destroy!
Onetime::Organization.load(@org3.objid).nil?
#=> true

# ---- Records with no canonical-name entry -----------------------------
#
# Domains registered before canonical_display_domain_index existed have no
# entry in it. Saving them with their name unchanged must keep working and
# must not add one: the entries are created by a separate backfill, not by
# whichever save comes first.

## a transfer saves a domain that has no canonical entry, and adds none
@pc_tdom = Onetime::CustomDomain.create!("dt-pc-transfer-#{@test_id}.example.com", @org1.objid)
@org1.add_domain(@pc_tdom)
@pc_tkey = Onetime::CustomDomain.canonical_display_domain(@pc_tdom.display_domain)
Onetime::CustomDomain.canonical_display_domain_index.remove_field(@pc_tkey)
@pc_t = Onetime::Operations::Domains::Transfer.new(
  domain: @pc_tdom, to_org: @org2, actor: @actor, dry_run: false,
).call
[@pc_t.status,
 Onetime::CustomDomain.find_by_identifier(@pc_tdom.identifier).org_id == @org2.org_id,
 Onetime::CustomDomain.canonical_display_domain_index.get(@pc_tkey)]
#=> [:transferred, true, nil]

## a repair that adopts an orphan with no canonical entry enters its name, like any other adoption
@pc_rseed = Onetime::CustomDomain.create!("dt-pc-repair-#{@test_id}.example.com", @org1.objid)
@pc_rkey  = Onetime::CustomDomain.canonical_display_domain(@pc_rseed.display_domain)
Onetime::CustomDomain.canonical_display_domain_index.remove_field(@pc_rkey)
@pc_rseed.remove_from_organization_domains(@org1)
Familia.dbclient.hset(@pc_rseed.dbkey, 'org_id', '')
@pc_rdom = Onetime::CustomDomain.find_by_identifier(@pc_rseed.domainid)
@pc_r = Onetime::Operations::Domains::Repair.new(domain: @pc_rdom, actor: @actor, org: @org2, dry_run: false).call
[@pc_r.status,
 Onetime::CustomDomain.find_by_identifier(@pc_rdom.identifier).org_id == @org2.org_id,
 Onetime::CustomDomain.canonical_display_domain_index.get(@pc_rkey) == @pc_rdom.identifier]
#=> [:repaired, true, true]

# ---- Adopting a verified orphan: Repair --org-id and Transfer ---------
#
# A verified, resolving orphan with a brand field; create! gave it the
# default homepage and api configs. Adoption resets the verification and
# issues a new TXT value, and reports what the record kept.

## Repair --org-id adopts a verified orphan and resets its verification
AE.events.clear
@ad_seed = Onetime::CustomDomain.create!("dt-adopt-repair-#{@test_id}.example.com", @org1.objid)
@ad_seed.brand['primary_color'] = '#336699'
@ad_seed.remove_from_organization_domains(@org1)
Familia.dbclient.hset(@ad_seed.dbkey, { 'org_id' => '', 'ownership_verified' => 'true', 'resolving' => 'true' })
Onetime::CustomDomain.owners.remove(@ad_seed.to_s)
@ad_dom = Onetime::CustomDomain.find_by_identifier(@ad_seed.domainid)
@ad_txt = @ad_dom.txt_validation_value
@ad_before = [@ad_dom.ownership_verified, @ad_dom.ready?]
@ad_r = Onetime::Operations::Domains::Repair.new(domain: @ad_dom, actor: @actor, org: @org2, dry_run: false).call
@ad_stored = Onetime::CustomDomain.find_by_identifier(@ad_dom.identifier)
[@ad_before, @ad_r.status, @ad_stored.org_id == @org2.org_id, @ad_stored.ownership_verified, @ad_stored.resolving,
 @ad_stored.ready?, @ad_stored.txt_validation_value == @ad_txt, @org2.domain?(@ad_stored),
 Onetime::CustomDomain.owners.get(@ad_stored.domainid) == @org2.objid]
#=> [[true, true], :repaired, true, false, false, false, false, true, true]

## the plan and the applied repairs say so, and list what the record kept
[@ad_r.issues,
 @ad_r.repairs_applied[1] == "Ownership verification reset; new TXT value #{@ad_stored.validation_record} = #{@ad_stored.txt_validation_value}",
 @ad_r.repairs_applied[2]]
#=> [['Domain is orphaned (no org_id); adopting it resets its ownership verification'], true, 'Kept from the earlier owner: configs: homepage, api; brand (1 field)']

## the repair's audit event records the adoption
@ad_ev = AE.recent(1).first
[@ad_ev['verb'], @ad_ev['target'] == @ad_dom.extid, @ad_ev['detail']['adopted_orphan'], @ad_ev['detail']['verification_reset']]
#=> ['domain.repair', true, true, true]

## a transfer from orphaned adopts a verified orphan the same way
AE.events.clear
@at_seed = Onetime::CustomDomain.create!("dt-adopt-transfer-#{@test_id}.example.com", @org1.objid)
@at_seed.remove_from_organization_domains(@org1)
Familia.dbclient.hdel(@at_seed.dbkey, 'org_id')
Familia.dbclient.hset(@at_seed.dbkey, { 'verified' => 'true', 'resolving' => 'true' })
Onetime::CustomDomain.owners.remove(@at_seed.to_s)
@at_key = Onetime::CustomDomain.canonical_display_domain(@at_seed.display_domain)
Onetime::CustomDomain.canonical_display_domain_index.remove_field(@at_key)
@at_dom = Onetime::CustomDomain.find_by_identifier(@at_seed.domainid)
@at_txt = @at_dom.txt_validation_value
@at_before = [@at_dom.ownership_verified, @at_dom.ready?]
@at_t = Onetime::Operations::Domains::Transfer.new(domain: @at_dom, to_org: @org2, actor: @actor, dry_run: false).call
@at_stored = Onetime::CustomDomain.find_by_identifier(@at_dom.identifier)
[@at_before, @at_t.status, @at_stored.org_id == @org2.org_id, @at_stored.ownership_verified, @at_stored.ready?,
 @at_stored.txt_validation_value == @at_txt, @org2.domain?(@at_stored),
 Onetime::CustomDomain.owners.get(@at_stored.domainid) == @org2.objid,
 Onetime::CustomDomain.canonical_display_domain_index.get(@at_key) == @at_stored.identifier]
#=> [[true, true], :transferred, true, false, false, false, true, true, true]

## the transfer result reports the adoption, and its audit event records it
@at_ev = AE.recent(1).first
[@at_t.adoption.configs, @at_t.adoption.txt_value == @at_stored.txt_validation_value,
 AE.count, @at_ev['detail']['adopted_orphan'], @at_ev['detail']['verification_reset']]
#=> [['homepage', 'api'], true, 1, true, true]

## a transfer between two organizations is not an adoption: no report, verification kept
Familia.dbclient.hset(@at_stored.dbkey, 'ownership_verified', 'true')
@at_live = Onetime::CustomDomain.find_by_identifier(@at_stored.identifier)
@at_live_txt = @at_live.txt_validation_value
@at_back = Onetime::Operations::Domains::Transfer.new(domain: @at_live, to_org: @org1, actor: @actor, dry_run: false).call
@at_after = Onetime::CustomDomain.find_by_identifier(@at_live.identifier)
[@at_back.status, @at_back.adoption, @at_after.org_id == @org1.org_id, @at_after.ownership_verified,
 @at_after.txt_validation_value == @at_live_txt]
#=> [:transferred, nil, true, true, true]

# ---- Cleanup ----------------------------------------------------------

[@orphan, @dom, @tdom, @rtdom, @pc_tdom, @pc_rdom, @ad_dom, @at_dom].compact.each { |d| d.destroy! rescue nil }
[@org1, @org2, @org3].compact.each { |o| o.destroy! rescue nil }
[@cust1, @cust2, @cust3].compact.each { |c| c.destroy! rescue nil }
AE.events.clear
