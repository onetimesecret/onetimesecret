# try/integration/api/colonel/upsert_domain_config_race_try.rb
#
# frozen_string_literal: true

# Focused coverage for the duplicate-create race rescue in
# Onetime::Operations::Domains::UpsertDomainConfig (PUT
# /api/colonel/domains/:extid/configs/:kind).
#
# The config models' create! raises Onetime::Problem for BOTH a lost
# duplicate-create race (the exists-guard, message '<Kind> config already
# exists for this domain') AND real attribute validation failures (e.g.
# allowed_signup_domains PublicSuffix rejection) — there is no distinct
# error class. The op's rescue must take the race path ONLY for the
# exists-guard collision:
#
# - a genuine race (record created between the op's read and create!)
#   falls back to the update path and still audits exactly once
# - a validation failure propagates UNCHANGED (422 form error at the
#   logic layer) without re-reading and WITHOUT re-applying the invalid
#   input to a concurrent writer's record — asserted here by counting
#   find_by_domain_id calls: exactly ONE (the initial read), never a
#   post-failure re-read
#
# The race interleavings are simulated by interposing on
# SignupConfig.find_by_domain_id (restored in the same test case).
#
# Run: try --agent try/integration/api/colonel/upsert_domain_config_race_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/domains/upsert_domain_config'

@timestamp = Familia.now.to_i
@klass     = Onetime::CustomDomain::SignupConfig

# The op only reads #identifier (record keying) and #extid (audit target),
# so a struct double stands in for a full CustomDomain.
@domain_race  = Struct.new(:identifier, :extid).new("upsert_race_r_#{@timestamp}", "cd_upsertr#{@timestamp}")
@domain_valid = Struct.new(:identifier, :extid).new("upsert_race_v_#{@timestamp}", "cd_upsertv#{@timestamp}")

# ----------------------------------------------------------------
# Genuine duplicate-create race -> update path
# ----------------------------------------------------------------

## Setup: the "concurrent writer's" record exists; our op's initial read
## misses it (interposed nil on the FIRST find only) so create! hits the
## exists-guard — the op must recover onto the update path
@klass.create!(domain_id: @domain_race.identifier)
@before_audit = Onetime::AdminAuditEvent.count
first_call = true
@klass.singleton_class.alias_method(:__race_real_find, :find_by_domain_id)
@klass.define_singleton_method(:find_by_domain_id) do |domain_id|
  if first_call
    first_call = false
    nil
  else
    __race_real_find(domain_id)
  end
end
begin
  @race_result = Onetime::Operations::Domains::UpsertDomainConfig.new(
    domain: @domain_race,
    kind: 'signup',
    attrs: { 'signup_enabled' => true },
    actor: 'colonel-race-test',
  ).call
  [@race_result.status, @race_result.changed]
ensure
  @klass.singleton_class.remove_method(:find_by_domain_id)
  @klass.singleton_class.alias_method(:find_by_domain_id, :__race_real_find)
  @klass.singleton_class.remove_method(:__race_real_find)
end
#=> [:updated, ['signup_enabled']]

## The raced record was updated in place and EXACTLY ONE audit event recorded
[
  @klass.find_by_domain_id(@domain_race.identifier).signup_enabled?,
  Onetime::AdminAuditEvent.count - @before_audit,
]
#=> [true, 1]

# ----------------------------------------------------------------
# Validation failure -> propagates, never takes the race path
# ----------------------------------------------------------------

## A model validation failure in create! (PublicSuffix-invalid
## allowed_signup_domains) re-raises UNCHANGED: find_by_domain_id is called
## exactly ONCE (the initial read) — the rescue never re-reads, so invalid
## input can never be applied to a record a concurrent writer created
@before_audit = Onetime::AdminAuditEvent.count
find_calls = []
@klass.singleton_class.alias_method(:__race_real_find, :find_by_domain_id)
@klass.define_singleton_method(:find_by_domain_id) do |domain_id|
  find_calls << domain_id
  __race_real_find(domain_id)
end
begin
  outcome = begin
    Onetime::Operations::Domains::UpsertDomainConfig.new(
      domain: @domain_valid,
      kind: 'signup',
      attrs: { 'allowed_signup_domains' => ['not_a_domain'] },
      actor: 'colonel-race-test',
    ).call
    'no raise'
  rescue Onetime::Problem => ex
    ex.message
  end
  [outcome.start_with?('Invalid domain: not_a_domain'), find_calls.size]
ensure
  @klass.singleton_class.remove_method(:find_by_domain_id)
  @klass.singleton_class.alias_method(:find_by_domain_id, :__race_real_find)
  @klass.singleton_class.remove_method(:__race_real_find)
end
#=> [true, 1]

## The failed upsert persisted nothing but recorded ONE result: :failure event
#
# Persisting nothing is the point of the race rescue; recording nothing was
# NOT. The validation raise happens after the write path was entered and
# before the success-path record call, so Onetime::AuditedFailure logs the
# attempt with the unchanged verb and re-raises (see the assertion above,
# which is still the original Onetime::Problem message).
[
  @klass.exists_for_domain?(@domain_valid.identifier),
  Onetime::AdminAuditEvent.count - @before_audit,
]
#=> [false, 1]

## the recorded event names the upsert verb, the domain, and result: failure
@race_evt = Onetime::AdminAuditEvent.recent(1, 0).first
[@race_evt['verb'], @race_evt['target'], @race_evt['result'],
 @race_evt['detail']['config'], @race_evt['detail']['changed']]
#=> ["domain.config_upsert", @domain_valid.extid, "failure", 'signup', ['allowed_signup_domains']]

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
Onetime::CustomDomain::SignupConfig.delete_for_domain!(@domain_race.identifier)  rescue nil
Onetime::CustomDomain::SignupConfig.delete_for_domain!(@domain_valid.identifier) rescue nil
