# try/unit/models/custom_domain/homepage_config_cidrs_try.rb
#
# frozen_string_literal: true

# Persistence tests for the HomepageConfig network rules (allowed_cidrs /
# denied_cidrs) through the real datastore: upsert merge semantics, the
# create! path the colonel ensure/upsert op uses, the ConfigRegistry
# coerce -> apply -> serialize round-trip, the safe_dump projection the
# workspace editor reads, and CustomDomain#allow_public_secret_creation?
# judging a visitor through a stand-in for env['otto.ip_match'].
#
# The in-memory decision table lives in
# spec/unit/onetime/models/custom_domain/homepage_config_network_spec.rb and
# spec/unit/onetime/utils/cidr_list_spec.rb; this file pins what survives a
# round-trip through Redis.

require_relative '../../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for HomepageConfig CIDR test run"

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_cidr_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpCidr Test Org #{@ts}", @owner, "hp_cidr_#{@ts}@test.com")
@domain  = Onetime::CustomDomain.create!("hp-cidr-#{@ts}.example.com", @org.objid)

# Stand-in for env['otto.ip_match']: membership of ONE client IP.
def matcher_for(ip)
  addr = IPAddr.new(ip)
  ->(ranges) { ranges.any? { |range| range.family == addr.family && range.include?(addr) } }
end

# --- bootstrap record: no rules ---

## The bootstrapped record carries no network rules and is unrestricted
cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
[cfg.allowed_cidrs, cfg.denied_cidrs, cfg.network_restricted?]
#=> [[], [], false]

## An unrestricted enabled create-mode homepage admits anonymous creation with no matcher
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true)
@domain.allow_public_secret_creation?
#=> true

# --- upsert: set, merge, clear ---

## upsert stores normalized, de-duplicated allowed ranges
@cfg = Onetime::CustomDomain::HomepageConfig.upsert(
  domain_id: @domain.identifier, enabled: true,
  allowed_cidrs: ['10.1.2.3/8', '10.0.0.0/8', '2001:DB8::/32'],
)
@cfg.allowed_cidrs
#=> ['10.0.0.0/8', '2001:db8::/32']

## The stored field is the JSON encoding of that list
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier).allowed_cidrs_json
#=> '["10.0.0.0/8","2001:db8::/32"]'

## upsert with the list omitted (nil) leaves it unchanged — merge semantics
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true, denied_cidrs: ['192.168.1.0/24'])
reloaded = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
[reloaded.allowed_cidrs, reloaded.denied_cidrs, reloaded.network_restricted?]
#=> [['10.0.0.0/8', '2001:db8::/32'], ['192.168.1.0/24'], true]

## upsert with [] clears a list (stored as nil)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true, denied_cidrs: [])
reloaded = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
[reloaded.denied_cidrs, reloaded.denied_cidrs_json]
#=> [[], nil]

## upsert refuses an unparseable entry with the typed error, before writing anything
before = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
begin
  Onetime::CustomDomain::HomepageConfig.upsert(
    domain_id: @domain.identifier, enabled: false, allowed_cidrs: ['10.0.0.0/8', 'not-a-range'],
  )
  :no_raise
rescue Onetime::CustomDomain::HomepageConfig::InvalidCidr => ex
  after = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
  [ex.field, ex.cidr, after.enabled?, after.allowed_cidrs == before.allowed_cidrs]
end
#=> ['allowed_cidrs', 'not-a-range', true, true]

# --- gate: allow_public_secret_creation? judged per visitor ---

## A visitor inside an allowed range may create secrets anonymously
@domain.allow_public_secret_creation?(ip_match: matcher_for('10.9.8.7'))
#=> true

## A visitor outside every allowed range may not
@domain.allow_public_secret_creation?(ip_match: matcher_for('203.0.113.9'))
#=> false

## With rules configured, a caller that supplies no matcher is refused (fail closed)
@domain.allow_public_secret_creation?
#=> false

## A denied range wins over the allow list
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true, denied_cidrs: ['10.9.0.0/16'])
[@domain.allow_public_secret_creation?(ip_match: matcher_for('10.9.8.7')),
 @domain.allow_public_secret_creation?(ip_match: matcher_for('10.8.8.7'))]
#=> [false, true]

## Network admission never overrides the mode gate (incoming mode still refuses creation)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true, secrets_mode: 'incoming')
@domain.allow_public_secret_creation?(ip_match: matcher_for('10.8.8.7'))
#=> false

Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain.identifier, enabled: true, secrets_mode: 'create')

# --- safe_dump projection (workspace domain record) ---

## The domain's safe_dump homepage_config block carries both lists
dump = Onetime::CustomDomain.find_by_identifier(@domain.identifier).safe_dump
[dump[:homepage_config][:allowed_cidrs], dump[:homepage_config][:denied_cidrs]]
#=> [['10.0.0.0/8', '2001:db8::/32'], ['10.9.0.0/16']]

# --- ConfigRegistry (colonel PUT path) ---

## coerce_field! accepts an array of strings for both fields
registry = Onetime::CustomDomain::ConfigRegistry
[registry.coerce_field!('homepage', 'allowed_cidrs', ['172.16.0.0/12']),
 registry.coerce_field!('homepage', 'denied_cidrs', [])]
#=> [['172.16.0.0/12'], []]

## coerce_field! rejects a non-array
begin
  registry.coerce_field!('homepage', 'allowed_cidrs', '172.16.0.0/12')
rescue Onetime::Problem => ex
  ex.message
end
#=> 'allowed_cidrs must be an array of strings'

## apply_field writes through the validating setter and the serializer emits the lists
cfg = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
registry.apply_field(cfg, 'homepage', 'allowed_cidrs', ['172.16.0.0/12', '172.16.5.0/12'])
registry.apply_field(cfg, 'homepage', 'denied_cidrs', [])
serialized = registry.serialize('homepage', cfg)
[serialized[:allowed_cidrs], serialized[:denied_cidrs]]
#=> [['172.16.0.0/12'], []]

## apply_field surfaces the typed refusal for an invalid entry
begin
  registry.apply_field(cfg, 'homepage', 'denied_cidrs', ['10.0.0.0/8', 'example.com'])
rescue Onetime::CustomDomain::HomepageConfig::InvalidCidr => ex
  [ex.field, ex.cidr, ex.error_key]
end
#=> ['denied_cidrs', 'example.com', 'api.domains.errors.homepage_cidr_invalid']

# --- create! (colonel upsert op on a missing record) ---

## create! accepts the lists as attrs and validates them
Onetime::CustomDomain::HomepageConfig.delete_for_domain!(@domain.identifier)
created = Onetime::CustomDomain::HomepageConfig.create!(
  domain_id: @domain.identifier, enabled: false, allowed_cidrs: ['198.51.100.0/24'], denied_cidrs: ['198.51.100.7'],
)
[created.allowed_cidrs, created.denied_cidrs, created.network_restricted?]
#=> [['198.51.100.0/24'], ['198.51.100.7/32'], true]

# --- teardown ---
@domain.destroy!
@org.destroy!
@owner.destroy!
