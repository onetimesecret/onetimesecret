# try/unit/models/custom_domain_load_contract_try.rb
#
# frozen_string_literal: true

# Tests for CustomDomain's Familia load(identifier) contract.
#
# Regression coverage for #3271: CustomDomain.load used to shadow Familia's
# load(identifier) with an incompatible (display_domain, org_id) signature,
# raising ArgumentError on every CustomDomain.load(objid) caller. The seven
# CLI doctor callers and JoinDomainOrganization all relied on the Familia
# idiom and broke the moment they ran. The old two-arg override could never
# return a record anyway: parse() builds a fresh object with a random objid
# (Familia.generate_id), so the obj.exists? guard always failed. It was
# removed rather than renamed.
#
# After the fix:
#   - CustomDomain.load(identifier) resolves through Familia's base loader
#     (same as find_by_identifier(identifier)).
#
# Run:
#   bundle exec try try/unit/models/custom_domain_load_contract_try.rb

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for CustomDomain.load contract test"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@fqdn = "load-contract-#{@ts}-#{@entropy}.example.com"
@owner = Onetime::Customer.create!(email: "load_contract_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Load Contract Org #{@ts}", @owner, "load_contract_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!(@fqdn, @org.objid)

# --- Familia contract: load(identifier) ---

## CustomDomain.load(identifier) returns the record for a known identifier
Onetime::CustomDomain.load(@domain.identifier).class
#=> Onetime::CustomDomain

## CustomDomain.load(identifier) returns the same record as find_by_identifier
Onetime::CustomDomain.load(@domain.identifier).identifier
#=> @domain.identifier

## CustomDomain.load(identifier) returns nil for unknown identifier
Onetime::CustomDomain.load('nonexistent-domain-id-xyz')
#=> nil

## CustomDomain.load(identifier) and find_by_identifier(identifier) agree
[
  Onetime::CustomDomain.load(@domain.identifier).identifier,
  Onetime::CustomDomain.find_by_identifier(@domain.identifier).identifier,
]
#=> [@domain.identifier, @domain.identifier]

# --- Two-arg load is gone (regression guard) ---
#
# The old shadowing override raised ArgumentError on single-arg callers.
# Make sure single-arg load is now the only signature CustomDomain exposes,
# so a future re-introduction of the two-arg form fails this test.

## CustomDomain.load no longer accepts (display_domain, org_id)
begin
  Onetime::CustomDomain.load(@fqdn, @org.objid)
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

# --- Doctor-style usage: scan instances and load by objid ---
#
# Mirrors lib/onetime/cli/domains/doctor_command.rb#scan_all_domains, which
# iterates CustomDomain.instances and calls CustomDomain.load(objid). Before
# the fix this raised ArgumentError on the first iteration.

## Iterating instances and calling load(objid) does not raise
@loaded_identifiers = Onetime::CustomDomain.instances.members.collect do |objid|
  Onetime::CustomDomain.load(objid)&.identifier
end.compact
@loaded_identifiers.include?(@domain.identifier)
#=> true

# --- recent() uses load(identifier) internally ---
#
# CustomDomain.recent iterates instances and calls load(identifier). Before
# the fix this raised on every call. The score-range edge means a domain
# created in the same second as now isn't guaranteed to be included, so we
# only assert the call doesn't raise.

## recent() runs without raising on the load(identifier) call inside the loop
Onetime::CustomDomain.recent.is_a?(Array)
#=> true

# Teardown
Familia.dbclient.flushdb
OT.info "Cleaned Redis after CustomDomain.load contract test"
