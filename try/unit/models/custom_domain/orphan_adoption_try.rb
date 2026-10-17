# try/unit/models/custom_domain/orphan_adoption_try.rb
#
# frozen_string_literal: true

# Adopting an orphaned custom domain (no org_id) for an organization:
# CustomDomain.claim_orphaned_domain, reached by create!(..., adopt_orphan: true)
# and by the operator tools.
#
# The adopted record keeps its identifier, so it would otherwise keep what an
# earlier owner left on it. Adoption resets that, in the same transaction as
# the new org_id:
#   - ownership_verified is stored as false, so a legacy `verified` value
#     still on the record no longer counts;
#   - resolving, verified_by_override, the confirmation timestamps and the
#     provider status (vhost, vhost_fetch_failed_at) are cleared;
#   - the TXT challenge gets a new value. Its host is derived from the
#     identifier and stays the same.
# The record is then pending, not ready, until the new owner verifies it.
#
# A concurrent write to the record between the WATCH and the EXEC still
# discards the adoption, and the record is left as it was.

require_relative '../../../support/test_models'

OT.boot! :test

@ts      = "#{Familia.now.to_i}-#{SecureRandom.hex(3)}"
@owner   = Onetime::Customer.create!(email: "adopt_owner_#{@ts}@test.com")
@earlier = Onetime::Organization.create!("Earlier Owner #{@ts}", @owner, "adopt-earlier-#{@ts}@test.com")
@adopter = Onetime::Organization.create!("Adopter #{@ts}", @owner, "adopt-adopter-#{@ts}@test.com")
@client  = Familia.dbclient
@index   = Onetime::CustomDomain.ascii_display_domain_index

# A verified, resolving orphan from an earlier owner. Its verification is in
# the legacy `verified` field only, it has no ASCII-name entry, and it is
# in no organization.
def verified_orphan(name, earlier_org)
  rec  = Onetime::CustomDomain.create!(name, earlier_org.objid)
  dump = ->(value) { Familia::JsonSerializer.dump(value) }
  @client.hdel(rec.dbkey, 'org_id', 'ownership_verified')
  @client.hset(rec.dbkey, {
    'verified' => dump.call(true),
    'resolving' => dump.call(true),
    'verified_by_override' => dump.call(true),
    'verified_confirmed_at' => dump.call(1_700_000_000),
    'verified_unconfirmed_since' => dump.call(1_700_000_100),
    'vhost' => dump.call('{"status":"ACTIVE_SSL"}'),
    'vhost_fetch_failed_at' => dump.call(1_700_000_200),
  })
  earlier_org.remove_domain(rec)
  Onetime::CustomDomain.owners.remove(rec.to_s)
  @index.remove_field(Onetime::CustomDomain.ascii_display_domain(name))
  Onetime::CustomDomain.find_by_identifier(rec.identifier)
end

## The orphan reads as verified and ready before adoption, from the legacy field alone
@name       = "adopt-#{@ts}.example.com"
@orphan     = verified_orphan(@name, @earlier)
@txt_host   = @orphan.txt_validation_host
@txt_value  = @orphan.txt_validation_value
[@orphan.org_id.to_s, @orphan.ownership_verified, @orphan.ready?, @client.hexists(@orphan.dbkey, 'ownership_verified')]
#=> ['', true, true, false]

## Adoption assigns the record to the organization
@adopted = Onetime::CustomDomain.claim_orphaned_domain(@orphan, @adopter.objid)
@stored  = Onetime::CustomDomain.find_by_identifier(@orphan.identifier)
[@adopted.identifier == @orphan.identifier, @stored.org_id == @adopter.objid]
#=> [true, true]

## ownership_verified is stored as false, so the legacy verified value no longer counts
[@stored.ownership_verified, @client.hget(@stored.dbkey, 'ownership_verified'), @client.hget(@stored.dbkey, 'verified')]
#=> [false, 'false', 'true']

## resolving, the override and the confirmation timestamps are cleared
[@stored.resolving, @stored.verified_by_override, @stored.verified_confirmed_at, @stored.verified_unconfirmed_since]
#=> [false, false, nil, nil]

## the provider status from the earlier owner is cleared
[@stored.vhost, @stored.vhost_fetch_failed_at, @client.hexists(@stored.dbkey, 'vhost')]
#=> [nil, nil, false]

## the TXT challenge keeps its host and gets a new value
[@stored.txt_validation_host == @txt_host, @stored.txt_validation_value == @txt_value,
 @stored.txt_validation_value.to_s.match?(/\A\h{32}\z/)]
#=> [true, false, true]

## the record is pending and not ready
[@stored.verification_state, @stored.ready?]
#=> [:pending, false]

## the returned record holds what was stored
[@adopted.ownership_verified, @adopted.resolving, @adopted.txt_validation_value == @stored.txt_validation_value]
#=> [false, false, true]

## the record's name is entered into the ASCII index for it
@index.get(Onetime::CustomDomain.ascii_display_domain(@name)) == @orphan.identifier
#=> true

## the record is in the organization and in the owners index
[@adopter.domain?(@stored), Onetime::CustomDomain.owners.get(@stored.to_s) == @adopter.objid]
#=> [true, true]

## create! with adopt_orphan: true adopts an orphan the same way
@name2   = "adopt-create-#{@ts}.example.com"
@orphan2 = verified_orphan(@name2, @earlier)
@value2  = @orphan2.txt_validation_value
@via_create = Onetime::CustomDomain.create!(@name2, @adopter.objid, adopt_orphan: true)
@stored2    = Onetime::CustomDomain.find_by_identifier(@orphan2.identifier)
[@via_create.identifier == @orphan2.identifier, @stored2.org_id == @adopter.objid,
 @stored2.ownership_verified, @stored2.ready?, @stored2.txt_validation_value == @value2]
#=> [true, true, false, false, false]

## a write to the record between the WATCH and the EXEC discards the adoption
@name3   = "adopt-race-#{@ts}.example.com"
@orphan3 = verified_orphan(@name3, @earlier)
@value3  = @orphan3.txt_validation_value
@orphan3.define_singleton_method(:atomic_write) do |*args, **opts, &block|
  # Same connection as the WATCH (it is pinned); a write by the watching
  # client also marks the key modified, so EXEC is discarded.
  Familia.dbclient.hset(dbkey, 'status', Familia::JsonSerializer.dump('touched'))
  super(*args, **opts, &block)
end
begin
  Onetime::CustomDomain.claim_orphaned_domain(@orphan3, @adopter.objid)
  :no_raise
rescue Onetime::TemporarilyUnavailable => ex
  ex.reason
end
#=> :concurrent_write

## the discarded adoption leaves the orphan as it was, and keeps the ASCII claim for the live record
@stored3 = Onetime::CustomDomain.find_by_identifier(@orphan3.identifier)
[@stored3.org_id.to_s, @stored3.ownership_verified, @stored3.txt_validation_value == @value3,
 @client.hexists(@stored3.dbkey, 'ownership_verified'),
 @index.get(Onetime::CustomDomain.ascii_display_domain(@name3)) == @orphan3.identifier]
#=> ['', true, true, false, true]

# Teardown
[@orphan, @orphan2, @orphan3].compact.each do |rec|
  Onetime::CustomDomain.find_by_identifier(rec.identifier)&.destroy!
rescue StandardError => ex
  warn "[orphan_adoption_try cleanup] #{ex.class}: #{ex.message}"
end
[@adopter, @earlier].each { |org| org.destroy! if org&.exists? }
@owner.destroy! if @owner&.exists?
