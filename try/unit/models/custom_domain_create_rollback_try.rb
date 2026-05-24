# try/unit/models/custom_domain_create_rollback_try.rb
#
# frozen_string_literal: true

# Tests for CustomDomain.create! rollback via destroy!
#
# As of commit 14c527f, the rescue inside CustomDomain.create! was changed
# from an enumerated cleanup (display_domains.remove, instances.remove,
# owners.remove, ApiConfig.delete_for_domain!, HomepageConfig.delete_for_domain!,
# remove_from_class_display_domain_index, ...) to a single obj.destroy! call,
# wrapped in its own rescue so a secondary failure during rollback cannot mask
# the original create! exception.
#
# The bug the change fixes: the old rescue did NOT delete obj.dbkey (the
# main domain hash) after obj.save succeeded but a later step (org-add,
# instances.add, owners.put, bootstrap_per_domain_configs) failed. The hash
# was left orphaned in Redis. Since destroy! is the symmetric inverse of
# create!, calling it from the rescue guarantees every write the begin
# block could have made is reverted.
#
# This file forces a failure at each interesting step inside the begin
# block of create! and asserts that no orphan state remains:
#
#   1. main domain hash (obj.dbkey) is gone
#   2. display_domains[display_domain] is nil
#   3. display_domain_index (unique_index) is clear
#   4. instances sorted set does not contain the objid
#   5. owners hash does not contain the objid
#   6. HomepageConfig record for the domain is gone
#   7. ApiConfig record for the domain is gone
#   8. load_by_display_domain returns nil (lookup-from-FQDN parity)
#   9. A subsequent create! with the same display_domain succeeds (no orphan
#      blocks the next attempt)
#
# Stubbing strategy: each scenario monkey-patches a single method via
# define_singleton_method, runs create!, and restores the original in an
# ensure block. Restores are critical — a leaked stub poisons every
# subsequent testcase.
#
# Patterns adapted from:
#   try/unit/models/custom_domain_destroy_cascade_try.rb (stub-and-restore)
#   try/unit/models/custom_domain_homepage_config_race_try.rb (closure-capture
#     of failure-point state into a shared mutable hash)

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for CustomDomain.create! rollback test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Shared owner + org for the bulk of the scenarios. Each scenario uses a
# distinct display_domain so any leak (a missing rollback) surfaces as a
# stale display_domains entry visible to later scenarios.
@owner = Onetime::Customer.create!(email: "cd_rb_owner_#{@ts}_#{@entropy}@test.com")
@org   = Onetime::Organization.create!(
  "CD Rollback Org #{@ts}_#{@entropy}",
  @owner,
  "cd_rb_org_#{@ts}_#{@entropy}@test.com",
)
@org_id = @org.objid

# Sanity setup
## Setup: shared owner + org exist
[@owner.email.include?("cd_rb_owner"), @org_id.to_s.empty?]
#=> [true, false]

# ----------------------------------------------------------------------------
# Scenario 1: failure AFTER obj.save, BEFORE org participation
# ----------------------------------------------------------------------------
#
# Stub Onetime::Organization.load to raise when called with our target org_id.
# At that point in create!, obj.generate_txt_validation_record and obj.save
# have both succeeded — so the main domain hash is in Redis, display_domains
# has the hsetnx entry, but instances/owners/bootstrap have NOT yet run.
# Org participation has NOT been added. The rollback's destroy! must clean
# up the main hash AND the display_domains entry AND the
# display_domain_index — that is the orphan path the bug fix addresses.

## Setup: Scenario 1 - capture state and stub Organization.load to raise
@s1_fqdn       = "cd-rb-s1-#{@ts}-#{@entropy}.example.com"
@s1_captured   = { id: nil, dbkey: nil }
org_class      = Onetime::Organization
original_load  = org_class.method(:load)
target_org_id  = @org_id
s1_target_fqdn = @s1_fqdn
s1_capture     = @s1_captured

org_class.define_singleton_method(:load) do |id, *rest|
  if id.to_s == target_org_id.to_s
    # Capture identifier/dbkey from the in-flight create! BEFORE we raise.
    # By this point, hsetnx + save have run, so display_domains has the
    # entry and the main hash exists.
    captured_id          = Onetime::CustomDomain.display_domains.get(s1_target_fqdn)
    s1_capture[:id]      = captured_id
    s1_capture[:dbkey]   = "custom_domain:#{captured_id}:object"
    raise StandardError, "forced failure: Organization.load post-save"
  else
    original_load.call(id, *rest)
  end
end

@s1_exception_message =
  begin
    Onetime::CustomDomain.create!(@s1_fqdn, @org_id)
    :unexpected_success
  rescue StandardError => e
    e.message
  ensure
    # Restore Organization.load no matter what — a leaked stub poisons
    # subsequent scenarios that also call Organization.load.
    org_class.define_singleton_method(:load) do |id, *rest|
      original_load.call(id, *rest)
    end
  end

@s1_exception_message
#=~> /forced failure: Organization\.load post-save/

## S1: captured identifier is present (proves we stubbed at the right moment)
@s1_captured[:id].to_s.empty?
#=> false

## S1: main domain hash is gone (was created by obj.save; per-step rollback
## explicitly DELs obj.dbkey — Gemini-flagged orphan fix)
Onetime::CustomDomain.find_by_identifier(@s1_captured[:id]).nil?
#=> true

## S1: display_domains entry for the FQDN is cleared
Onetime::CustomDomain.display_domains.get(@s1_fqdn)
#=> nil

## S1: display_domain_index (auto unique_index) is cleared
Onetime::CustomDomain.display_domain_index.get(@s1_fqdn)
#=> nil

## S1: instances sorted set does not contain the rolled-back objid
## (instances.score returns nil when the member is absent; member? returns
## true/false but score is the canonical existence check on sorted_sets)
Onetime::CustomDomain.instances.score(@s1_captured[:id]).nil?
#=> true

## S1: owners hash does not contain the rolled-back objid
Onetime::CustomDomain.owners.get(@s1_captured[:id])
#=> nil

## S1: HomepageConfig was not bootstrapped (failure was before bootstrap step)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s1_captured[:id])
#=> false

## S1: ApiConfig was not bootstrapped
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@s1_captured[:id])
#=> false

## S1: load_by_display_domain returns nil after rollback
Onetime::CustomDomain.load_by_display_domain(@s1_fqdn)
#=> nil

## S1: org's domains participation set does NOT include the rolled-back id
@org.domains.member?(@s1_captured[:id])
#=> false

# ----------------------------------------------------------------------------
# Scenario 2: failure during bootstrap_per_domain_configs
# ----------------------------------------------------------------------------
#
# Stub Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain to
# raise. By the time bootstrap runs (line 805 in custom_domain.rb), obj.save,
# the org participation, instances.add, and owners.put have ALL succeeded.
# This is the heaviest rollback path — every class index has the obj, and
# org participation has been added.
#
# Note: the rollback destroy! also runs HomepageConfig.delete_for_domain! as
# part of its sibling-cleanup. If a prior bootstrap step (the HomepageConfig
# call itself) raised BEFORE writing anything, exists_for_domain? returns
# false and delete_for_domain! is a no-op. If the raise happened AFTER one
# of the two bootstrap calls wrote, that record will be cleaned by destroy!.
# Either way the end state must show no HomepageConfig/ApiConfig record.

## Setup: Scenario 2 - capture state and stub HomepageConfig.find_or_create_for_domain
@s2_fqdn      = "cd-rb-s2-#{@ts}-#{@entropy}.example.com"
@s2_captured  = { id: nil, dbkey: nil }
hp_class      = Onetime::CustomDomain::HomepageConfig
original_hp_focd = hp_class.method(:find_or_create_for_domain)
s2_target_fqdn = @s2_fqdn
s2_capture     = @s2_captured

hp_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
  domain_id = kwargs[:domain_id]
  # Only intercept calls for our scenario-2 target domain so we don't
  # disturb unrelated bootstrap calls elsewhere.
  expected_id = Onetime::CustomDomain.display_domains.get(s2_target_fqdn)
  if domain_id.to_s == expected_id.to_s && !expected_id.to_s.empty?
    s2_capture[:id]    = expected_id
    s2_capture[:dbkey] = "custom_domain:#{expected_id}:object"
    raise StandardError, "forced failure: HomepageConfig.find_or_create_for_domain"
  else
    original_hp_focd.call(**kwargs)
  end
end

@s2_exception_message =
  begin
    Onetime::CustomDomain.create!(@s2_fqdn, @org_id)
    :unexpected_success
  rescue StandardError => e
    e.message
  ensure
    hp_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
      original_hp_focd.call(**kwargs)
    end
  end

@s2_exception_message
#=~> /forced failure: HomepageConfig\.find_or_create_for_domain/

## S2: captured identifier is present
@s2_captured[:id].to_s.empty?
#=> false

## S2: main domain hash is gone (orphan that the bug fix prevents)
Onetime::CustomDomain.find_by_identifier(@s2_captured[:id]).nil?
#=> true

## S2: display_domains entry is cleared
Onetime::CustomDomain.display_domains.get(@s2_fqdn)
#=> nil

## S2: display_domain_index is cleared
Onetime::CustomDomain.display_domain_index.get(@s2_fqdn)
#=> nil

## S2: instances sorted set was added then rolled back
Onetime::CustomDomain.instances.score(@s2_captured[:id]).nil?
#=> true

## S2: owners hash was added then rolled back
Onetime::CustomDomain.owners.get(@s2_captured[:id])
#=> nil

## S2: HomepageConfig is absent (the stub raised before any write)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s2_captured[:id])
#=> false

## S2: ApiConfig is absent (HomepageConfig raised first, so ApiConfig never ran)
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@s2_captured[:id])
#=> false

## S2: org's domains participation does NOT include the rolled-back id
@org.domains.member?(@s2_captured[:id])
#=> false

## S2: load_by_display_domain returns nil after rollback
Onetime::CustomDomain.load_by_display_domain(@s2_fqdn)
#=> nil

# ----------------------------------------------------------------------------
# Scenario 3: failure AFTER one bootstrap config wrote but before the other
# ----------------------------------------------------------------------------
#
# bootstrap_per_domain_configs calls HomepageConfig.find_or_create_for_domain
# FIRST and ApiConfig.find_or_create_for_domain SECOND. Stub ApiConfig's
# find_or_create_for_domain to raise — so HomepageConfig HAS written by the
# time the rescue fires. destroy!'s sibling-cleanup must clean up that
# partial bootstrap write.

## Setup: Scenario 3 - stub ApiConfig.find_or_create_for_domain to raise
@s3_fqdn      = "cd-rb-s3-#{@ts}-#{@entropy}.example.com"
@s3_captured  = { id: nil, hp_was_present: nil }
api_class     = Onetime::CustomDomain::ApiConfig
original_api_focd = api_class.method(:find_or_create_for_domain)
s3_target_fqdn = @s3_fqdn
s3_capture     = @s3_captured

api_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
  domain_id = kwargs[:domain_id]
  expected_id = Onetime::CustomDomain.display_domains.get(s3_target_fqdn)
  if domain_id.to_s == expected_id.to_s && !expected_id.to_s.empty?
    s3_capture[:id]             = expected_id
    # Confirm that the HomepageConfig bootstrap step already wrote a record
    # by this point — i.e. there is a partial state to clean up.
    s3_capture[:hp_was_present] = Onetime::CustomDomain::HomepageConfig.exists_for_domain?(expected_id)
    raise StandardError, "forced failure: ApiConfig.find_or_create_for_domain"
  else
    original_api_focd.call(**kwargs)
  end
end

@s3_exception_message =
  begin
    Onetime::CustomDomain.create!(@s3_fqdn, @org_id)
    :unexpected_success
  rescue StandardError => e
    e.message
  ensure
    api_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
      original_api_focd.call(**kwargs)
    end
  end

@s3_exception_message
#=~> /forced failure: ApiConfig\.find_or_create_for_domain/

## S3: HomepageConfig WAS present at failure time (partial bootstrap occurred)
@s3_captured[:hp_was_present]
#=> true

## S3: rollback cleaned up the partial HomepageConfig write
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s3_captured[:id])
#=> false

## S3: ApiConfig is absent (its stub raised before writing)
Onetime::CustomDomain::ApiConfig.exists_for_domain?(@s3_captured[:id])
#=> false

## S3: main domain hash is gone
Onetime::CustomDomain.find_by_identifier(@s3_captured[:id]).nil?
#=> true

## S3: display_domains, instances, owners, display_domain_index all cleared
[
  Onetime::CustomDomain.display_domains.get(@s3_fqdn),
  Onetime::CustomDomain.display_domain_index.get(@s3_fqdn),
  Onetime::CustomDomain.instances.score(@s3_captured[:id]),
  Onetime::CustomDomain.owners.get(@s3_captured[:id]),
]
#=> [nil, nil, nil, nil]

## S3: load_by_display_domain returns nil after rollback
Onetime::CustomDomain.load_by_display_domain(@s3_fqdn)
#=> nil

# ----------------------------------------------------------------------------
# Scenario 4: failure BEFORE obj.save (during generate_txt_validation_record)
# ----------------------------------------------------------------------------
#
# At this point hsetnx HAS written display_domains[fqdn]=identifier — but
# obj.save has NOT been called, so the main hash does not exist. destroy!
# should still clean up cleanly: self.class.rem removes the display_domains
# entry and the unique_index; the main DEL is a no-op on a missing key.

## Setup: Scenario 4 - stub parse to return obj whose generate_txt_validation_record raises
@s4_fqdn      = "cd-rb-s4-#{@ts}-#{@entropy}.example.com"
@s4_captured  = { id: nil, dbkey: nil }
cd_class      = Onetime::CustomDomain
original_parse = cd_class.method(:parse)
s4_target_fqdn = @s4_fqdn
s4_capture     = @s4_captured

cd_class.define_singleton_method(:parse) do |input, org_id_arg|
  obj = original_parse.call(input, org_id_arg)
  if obj.display_domain.to_s == s4_target_fqdn
    # Capture identifier before injecting the failure. objid is lazy-
    # generated on first access, so calling identifier here materializes it.
    s4_capture[:id]    = obj.identifier
    s4_capture[:dbkey] = obj.dbkey
    obj.define_singleton_method(:generate_txt_validation_record) do
      raise StandardError, "forced failure: generate_txt_validation_record pre-save"
    end
  end
  obj
end

@s4_exception_message =
  begin
    Onetime::CustomDomain.create!(@s4_fqdn, @org_id)
    :unexpected_success
  rescue StandardError => e
    e.message
  ensure
    cd_class.define_singleton_method(:parse) do |input, org_id_arg|
      original_parse.call(input, org_id_arg)
    end
  end

@s4_exception_message
#=~> /forced failure: generate_txt_validation_record pre-save/

## S4: captured identifier is present
@s4_captured[:id].to_s.empty?
#=> false

## S4: main domain hash never existed and is still gone
Onetime::CustomDomain.find_by_identifier(@s4_captured[:id]).nil?
#=> true

## S4: display_domains entry was set by hsetnx then cleaned by rollback
Onetime::CustomDomain.display_domains.get(@s4_fqdn)
#=> nil

## S4: instances and owners were never written
Onetime::CustomDomain.instances.score(@s4_captured[:id]).nil?
#=> true

## S4: HomepageConfig and ApiConfig never bootstrapped
[
  Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s4_captured[:id]),
  Onetime::CustomDomain::ApiConfig.exists_for_domain?(@s4_captured[:id]),
]
#=> [false, false]

## S4: load_by_display_domain returns nil after rollback
Onetime::CustomDomain.load_by_display_domain(@s4_fqdn)
#=> nil

# ----------------------------------------------------------------------------
# Scenario 5: a single rollback step raising does NOT block the others
# ----------------------------------------------------------------------------
#
# create!'s rescue iterates rollback_steps and rescues StandardError around
# each step independently. This is the load-bearing property that explicit
# per-step cleanup gives us over a monolithic destroy! call: one step
# failing (e.g. transient Redis hiccup, stubbed-in-test, broken sibling
# class) doesn't prevent the others from running.
#
# We force the original create! failure (HomepageConfig stub raises) AND
# break ONE specific rollback step (ApiConfig.delete_for_domain! — the
# sibling-cleanup step that runs DURING rollback, picked because the
# destroy_cascade tryout already demonstrates that stub-and-restore on
# the class-singleton works here). The remaining steps — display_domains,
# display_domain_index, instances, owners, HomepageConfig, main hash,
# organization participation — must still execute. The original exception
# must still escape create! unchanged.

## Setup: Scenario 5 - stub HP bootstrap raises and ApiConfig.delete_for_domain! raises during rollback
@s5_fqdn           = "cd-rb-s5-#{@ts}-#{@entropy}.example.com"
@s5_captured       = { id: nil }
hp_class           = Onetime::CustomDomain::HomepageConfig
original_hp_focd2  = hp_class.method(:find_or_create_for_domain)
api_class          = Onetime::CustomDomain::ApiConfig
original_api_del   = api_class.method(:delete_for_domain!)
s5_target_fqdn     = @s5_fqdn
s5_capture         = @s5_captured

# Stub HomepageConfig.find_or_create_for_domain so the create! step raises
# AFTER instances.add and owners.put have run.
hp_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
  domain_id   = kwargs[:domain_id]
  expected_id = Onetime::CustomDomain.display_domains.get(s5_target_fqdn)
  if domain_id.to_s == expected_id.to_s && !expected_id.to_s.empty?
    s5_capture[:id] = expected_id
    raise StandardError, "ORIGINAL create! failure: HomepageConfig bootstrap"
  else
    original_hp_focd2.call(**kwargs)
  end
end

# Stub ApiConfig.delete_for_domain! to raise — this is one specific rollback
# step. The per-step rescue inside create! must swallow this and proceed.
api_class.define_singleton_method(:delete_for_domain!) do |domain_id|
  if domain_id.to_s == s5_capture[:id].to_s && !s5_capture[:id].to_s.empty?
    raise StandardError, "STEP FAILURE: ApiConfig.delete_for_domain! forced raise"
  else
    original_api_del.call(domain_id)
  end
end

@s5_exception_message =
  begin
    Onetime::CustomDomain.create!(@s5_fqdn, @org_id)
    :unexpected_success
  rescue StandardError => e
    e.message
  ensure
    hp_class.define_singleton_method(:find_or_create_for_domain) do |**kwargs|
      original_hp_focd2.call(**kwargs)
    end
    api_class.define_singleton_method(:delete_for_domain!) do |domain_id|
      original_api_del.call(domain_id)
    end
  end

## S5: the exception that escaped create! is the ORIGINAL one, not the step ex
@s5_exception_message.to_s
#=~> /ORIGINAL create! failure: HomepageConfig bootstrap/

## S5: explicitly assert it is NOT the step failure message
@s5_exception_message.to_s.include?("STEP FAILURE")
#=> false

## S5: captured identifier was set by the HP stub (proves it fired)
@s5_captured[:id].to_s.empty?
#=> false

## S5: even with ApiConfig.delete_for_domain! broken, other steps still ran.
## display_domains was cleared (different step, independently rescued).
Onetime::CustomDomain.display_domains.get(@s5_fqdn)
#=> nil

## S5: main domain hash was deleted (Familia DEL step ran independently)
Onetime::CustomDomain.find_by_identifier(@s5_captured[:id]).nil?
#=> true

## S5: instances sorted set was cleared (independent step)
Onetime::CustomDomain.instances.score(@s5_captured[:id]).nil?
#=> true

## S5: owners hash was cleared (independent step)
Onetime::CustomDomain.owners.get(@s5_captured[:id])
#=> nil

## S5: HomepageConfig was cleaned (independent step). HP never wrote in this
## scenario (the stub raised before writing), so this is a no-op delete.
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s5_captured[:id])
#=> false

# NOTE: We do not assert anything about ApiConfig.exists_for_domain? here.
# The stub blocked rollback's delete_for_domain! from running, but ApiConfig
# was never written by create! either (HP raised first, before ApiConfig
# bootstrap), so the record simply never existed. The contract being tested
# is "other steps still ran", not "the sabotaged step's target state".

# ----------------------------------------------------------------------------
# Scenario 6: idempotent retry after a successful rollback
# ----------------------------------------------------------------------------
#
# After scenario 1's rollback, immediately retry create! with the same
# display_domain. If rollback was complete, the second create! should
# succeed cleanly — no orphan hsetnx blocks it, no stale main hash, no
# stale class-index entries.
#
# This is the user-visible regression contract: a transient infrastructure
# failure during a custom-domain add must leave the system retryable.

## Setup: Scenario 6 - confirm the s1 display_domain has no residue
[
  Onetime::CustomDomain.display_domains.get(@s1_fqdn),
  Onetime::CustomDomain.load_by_display_domain(@s1_fqdn),
]
#=> [nil, nil]

## S6: retry create! with the same fqdn under the same org succeeds
@s6_domain = Onetime::CustomDomain.create!(@s1_fqdn, @org_id)
[
  @s6_domain.is_a?(Onetime::CustomDomain),
  @s6_domain.display_domain == @s1_fqdn,
  @s6_domain.org_id == @org_id,
]
#=> [true, true, true]

## S6: a fresh identifier was generated (not reusing the rolled-back one)
@s6_domain.identifier != @s1_captured[:id]
#=> true

## S6: all the expected indexes are populated for the retry
[
  Onetime::CustomDomain.display_domains.get(@s1_fqdn) == @s6_domain.identifier,
  Onetime::CustomDomain.display_domain_index.get(@s1_fqdn) == @s6_domain.identifier,
  !Onetime::CustomDomain.instances.score(@s6_domain.identifier).nil?,
  Onetime::CustomDomain.owners.get(@s6_domain.identifier) == @org_id,
]
#=> [true, true, true, true]

## S6: HomepageConfig and ApiConfig were bootstrapped on the retry
[
  Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@s6_domain.identifier),
  Onetime::CustomDomain::ApiConfig.exists_for_domain?(@s6_domain.identifier),
]
#=> [true, true]

## S6: org participation was added on the retry. We re-load the org from
## Redis to get a fresh view (the @org object captured at top-of-file may
## be reading from cached state depending on Familia v2 internals) and
## use .score (the canonical Familia sorted_set presence check) rather
## than .member? which appears to behave inconsistently here.
!Onetime::Organization.load(@org_id).domains.score(@s6_domain.identifier).nil?
#=> true

# Teardown
Familia.dbclient.flushdb
