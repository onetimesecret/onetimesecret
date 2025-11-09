# try/unit/models/custom_domain_familia_v2_try.rb
#
# Familia v2 relationship validation tests for CustomDomain model
# Tests verify migration from custid ownership to org_id-based ownership
#
# CRITICAL: CustomDomain should use participates_in Organization, :domains
# This auto-generates:
# - org.domains (sorted_set) - auto-created by CustomDomain participation
# - domain.organization_instances - reverse lookup to owning org
# - domain.add_to_organization_domains(org) - add domain to org
# - domain.remove_from_organization_domains(org) - remove from org
# - org.add_domains_instance(domain) - bidirectional add
# - org.remove_domains_instance(domain) - bidirectional remove
#
# Migration strategy tested:
# 1. Remove custid field from CustomDomain
# 2. Add org_id field to CustomDomain
# 3. Add participates_in Organization, :domains to CustomDomain
# 4. Update create! to accept org_id instead of custid
# 5. Migrate access patterns: Customer -> Organization -> Domains

require_relative '../../support/test_models'

begin
  OT.boot! :test, false
rescue Redis::CannotConnectError, Redis::ConnectionError => e
  puts "SKIP: Requires Redis connection (#{e.class})"
  exit 0
end

# Clean up any existing test data from previous runs
if ENV['ENV'] == 'test'
  Familia.dbclient.flushdb
  OT.info "Cleaned Redis for fresh test run"
end

# Setup test fixtures
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "domain_owner_#{@timestamp}@test.com")
@member = Onetime::Customer.create!(email: "domain_member_#{@timestamp}@test.com")

## Creating organization for domain ownership
@org = Onetime::Organization.create!("Acme Corp", @owner, "domains@acme.com")
[@org.class, @org.display_name, @org.owner_id]
#=> [Onetime::Organization, "Acme Corp", @owner.custid]

## Organization has auto-generated domains collection (from CustomDomain.participates_in)
@org.respond_to?(:domains)
#=> true

## Domains collection is a Familia::SortedSet
@org.domains.class
#=> Familia::SortedSet

## Domains collection starts empty
@org.domains.size
#=> 0

## Create custom domain with org_id instead of custid
@domain_input = "secrets.acme.com"
@domain = Onetime::CustomDomain.create!(@domain_input, @org.orgid)
[@domain.class, @domain.display_domain]
#=> [Onetime::CustomDomain, "secrets.acme.com"]

## Domain has org_id field set
@domain.org_id
#=> @org.orgid

## Domain does NOT have custid field (migration complete)
@domain.respond_to?(:custid)
#=> false

## Domain appears in organization's domains collection
@org.domains.member?(@domain.objid)
#=> true

## Domains collection size incremented
@org.domains.size
#=> 1

## Domain has reverse relationship method (domain -> organizations)
@domain.respond_to?(:organization_instances)
#=> true

## Domain participations tracked in Redis
@domain.participations.to_a.any? { |p| p.include?(@org.orgid) }
#=> true

## Domain can find its owning organization
@orgs = @domain.organization_instances
@orgs.size
#=> 1

## Owning organization is correct
@orgs.first.orgid
#=> @org.orgid

## Create second domain for same organization
@domain2 = Onetime::CustomDomain.create!("api.acme.com", @org.orgid)
@domain2.display_domain
#=> "api.acme.com"

## Organization has multiple domains
@org.domains.size
#=> 2

## List all domains with bulk loading (convenience method)
@org_domains = @org.list_domains
@org_domains.size
#=> 2

## All domains are CustomDomain instances
@org_domains.all? { |d| d.is_a?(Onetime::CustomDomain) }
#=> true

## Domains include both domain instances
@org_domains.map(&:display_domain).sort
#=> ["api.acme.com", "secrets.acme.com"]

## Domain count returns accurate count (without loading instances)
@org.domain_count
#=> 2

## Unique index on display_domain prevents duplicates
begin
  Onetime::CustomDomain.create!("secrets.acme.com", @org.orgid)
  false
rescue Onetime::Problem => e
  e.message.include?('Duplicate domain')
end
#=> true

## Multi-index on org_id enables org-scoped queries
@org_domain_ids = Onetime::CustomDomain.find_all_by_org_id(@org.orgid)
@org_domain_ids.size
#=> 2

## Index lookups return correct domain identifiers
@org_domain_ids.sort
#=> [@domain.domainid, @domain2.domainid].sort

## Domain belongs to exactly one organization
@domain.organization_instances.size
#=> 1

## Removing domain from organization updates both sides
@org.remove_domain(@domain2)
@org.domain_count
#=> 1

## Domain participations cleaned after removal
@domain2.participations.to_a.any? { |p| p.include?(@org.orgid) }
#=> false

## Domain no longer in organization's collection
@org.domains.member?(@domain2.objid)
#=> false

## Bidirectional add using domain method
@domain2.add_to_organization_domains(@org, Familia.now.to_f)
@org.domain_count
#=> 2

## Organization collection updated after bidirectional add
@org.domains.member?(@domain2.objid)
#=> true

## Bidirectional remove using domain method
@domain2.remove_from_organization_domains(@org)
@org.domain_count
#=> 1

## Access pattern: Customer -> Organization -> Domains
@owner_orgs = @owner.organization_instances
@owner_orgs.first.list_domains.size
#=> 1

## Access pattern: Team Member -> Team -> Organization -> Domains
@team = Onetime::Team.create!("Engineering", @owner, @org.orgid)
@team_org = Onetime::Organization.load(@team.orgid)
@team_org.list_domains.map(&:display_domain)
#=> ["secrets.acme.com"]

## Add member to organization using auto-generated method
@org.add_members_instance(@member)
@org.member?(@member)
#=> true

## Member can access organization's domains
@member_orgs = @member.organization_instances
@member_orgs.first.list_domains.size
#=> 1

## Create second organization for isolation testing
@org2 = Onetime::Organization.create!("Widget Inc", @member, "domains@widget.com")
@domain3 = Onetime::CustomDomain.create!("secrets.widget.com", @org2.orgid)
@domain3.display_domain
#=> "secrets.widget.com"

## First org does not see second org's domains
@org.list_domains.map(&:display_domain)
#=> ["secrets.acme.com"]

## Second org has its own domain
@org2.list_domains.map(&:display_domain)
#=> ["secrets.widget.com"]

## Domain can only belong to one organization (no multi-org support)
@domain.organization_instances.size
#=> 1

## Attempting to add domain to second org fails
begin
  @org2.add_domain(@domain)
  false
rescue StandardError
  true
end
#=> true

## Orphaned domain handling: domain without organization
@orphan = Onetime::CustomDomain.new(display_domain: "orphan.example.com", org_id: nil)
@orphan.org_id.nil?
#=> true

## Orphaned domain cannot be saved (org_id required)
begin
  @orphan.save
  false
rescue Onetime::Problem => e
  e.message.include?('required') || e.message.include?('Organization')
end
#=> true

## Domain deletion removes from organization
@domain.destroy!
@org.domain_count
#=> 0

## Deleted domain no longer exists
@domain.exists?
#=> false

## Domain removed from organization's collection after destroy
@org.domains.member?(@domain.objid)
#=> false

## Organization deletion validation when domains exist
@org2.domain_count
#=> 1

## Cannot delete organization with domains (business rule)
begin
  @org2.destroy!
  false
rescue Onetime::Problem => e
  e.message.include?('domain') || e.message.include?('Cannot delete')
end
#=> true

## Can delete organization after removing all domains
@org2.remove_domain(@domain3)
@domain3.destroy!
@org2.destroy!
!@org2.exists?
#=> true

## Display domain lookup works correctly
@existing_domain = Onetime::CustomDomain.from_display_domain("api.acme.com")
@existing_domain.display_domain
#=> "api.acme.com"

## Display domain lookup returns nil for non-existent domains
@nonexistent = Onetime::CustomDomain.from_display_domain("nonexistent.acme.com")
@nonexistent.nil?
#=> true

## TXT validation record generation works with org_id
@domain2.generate_txt_validation_record
@domain2.txt_validation_host.start_with?('_onetime-challenge-')
#=> true

## TXT validation value is 32-char hex
@domain2.txt_validation_value.match?(/\A[a-f0-9]{32}\z/)
#=> true

## Domain verification state tracking
@domain2.verification_state
#=> :pending

## Domain is not ready until verified
@domain2.ready?
#=> false

## Domain owner is organization owner
@domain2_org = @domain2.organization_instances.first
@domain2_org.owner_id
#=> @owner.custid

## Convenience method: add_domain works
@domain4 = Onetime::CustomDomain.new(display_domain: "links.acme.com", org_id: @org.orgid)
@domain4.save
@org.add_domain(@domain4)
@org.domain_count
#=> 2

## Convenience method: remove_domain works
@org.remove_domain(@domain4)
@org.domain_count
#=> 1

# Teardown
@domain4.destroy! if @domain4&.exists?
@domain3.destroy! if @domain3&.exists?
@domain2.destroy! if @domain2&.exists?
@team.destroy! if @team&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
@member.destroy! if @member&.exists?
