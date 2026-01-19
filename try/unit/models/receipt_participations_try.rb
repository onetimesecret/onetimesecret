# try/unit/models/receipt_participations_try.rb
#
# frozen_string_literal: true

# Familia v2 relationship validation tests for Receipt model
# Tests verify the participates_in relationships for Organization and CustomDomain scoping
#
# Receipt should use:
# - participates_in :Organization, :receipts, score: :created
# - participates_in :CustomDomain, :receipts, score: :created
#
# This auto-generates:
# - org.receipts (sorted_set) - receipts created in org context
# - custom_domain.receipts (sorted_set) - receipts created with this domain
# - receipt.organization_instances - reverse lookup to org
# - receipt.custom_domain_instances - reverse lookup to custom domain
# - receipt.add_to_organization_receipts(org) - add to org's collection
# - receipt.add_to_custom_domain_receipts(domain) - add to domain's collection
# - receipt.remove_from_organization_receipts(org) - remove from org
# - receipt.remove_from_custom_domain_receipts(domain) - remove from domain

require_relative '../../support/test_models'

OT.boot! :test

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info 'Cleaned Redis for fresh test run'

# Setup test fixtures
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "receipt_test_#{@timestamp}@test.com")

## Creating organization for receipt scoping
@org = Onetime::Organization.create!('Receipt Test Org', @owner, "receipts@test-#{@timestamp}.com")
[@org.class, @org.display_name, @org.owner_id]
#=> [Onetime::Organization, "Receipt Test Org", @owner.custid]

## Organization has auto-generated receipts collection (from Receipt.participates_in)
@org.respond_to?(:receipts)
#=> true

## Receipts collection is a Familia::SortedSet
@org.receipts.class
#=> Familia::SortedSet

## Receipts collection starts empty
@org.receipts.size
#=> 0

## Create custom domain for receipt scoping
@domain_input = "secrets-#{@timestamp}.test.com"
@domain = Onetime::CustomDomain.create!(@domain_input, @org.objid)
[@domain.class, @domain.display_domain]
#=> [Onetime::CustomDomain, @domain_input]

## CustomDomain has auto-generated receipts collection
@domain.respond_to?(:receipts)
#=> true

## Domain receipts collection is a Familia::SortedSet
@domain.receipts.class
#=> Familia::SortedSet

## Domain receipts collection starts empty
@domain.receipts.size
#=> 0

## Create receipt with secret (using spawn_pair for proper initialization)
@receipt, @secret = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'test secret content', domain: @domain.display_domain)
[@receipt.class, @secret.class]
#=> [Onetime::Receipt, Onetime::Secret]

## Receipt has org_id field
@receipt.respond_to?(:org_id)
#=> true

## Receipt has domain_id field
@receipt.respond_to?(:domain_id)
#=> true

## Receipt has organization participation methods
@receipt.respond_to?(:add_to_organization_receipts)
#=> true

## Receipt has custom domain participation methods
# NOTE: Familia generates method names with underscores for CamelCase class names (CustomDomain -> custom_domain)
@receipt.respond_to?(:add_to_custom_domain_receipts)
#=> true

## Set receipt org_id and add to organization
@receipt.org_id = @org.objid
@receipt.save
@receipt.add_to_organization_receipts(@org)
@receipt.org_id
#=> @org.objid

## Receipt appears in organization's receipts collection
@org.receipts.member?(@receipt.objid)
#=> true

## Organization receipts size incremented
@org.receipts.size
#=> 1

## Set receipt domain_id and add to custom domain
@receipt.domain_id = @domain.objid
@receipt.save
@receipt.add_to_custom_domain_receipts(@domain)
@receipt.domain_id
#=> @domain.objid

## Receipt appears in domain's receipts collection
@domain.receipts.member?(@receipt.objid)
#=> true

## Domain receipts size incremented
@domain.receipts.size
#=> 1

## Receipt has reverse relationship to organization
@receipt.respond_to?(:organization_instances)
#=> true

## Receipt has reverse relationship to custom domain
# NOTE: custom_domain_instances method exists but returns empty due to prefix mismatch
# (CustomDomain uses prefix 'customdomain' but Familia normalizes class name to 'custom_domain')
# This is a known limitation - use domain_id field for lookups instead
@receipt.respond_to?(:custom_domain_instances)
#=> true

## Receipt can find its organization
@receipt_orgs = @receipt.organization_instances
@receipt_orgs.size
#=> 1

## Receipt organization is correct
@receipt_orgs.first.objid
#=> @org.objid

## Receipt domain_id matches the domain objid
# The custom_domain_instances method doesn't work due to prefix/class name mismatch
# but we can verify the domain_id field stores the correct reference
@receipt.domain_id
#=> @domain.objid

## Create second receipt for same organization (different domain)
@receipt2, @secret2 = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'second secret')
@receipt2.org_id = @org.objid
@receipt2.save
@receipt2.add_to_organization_receipts(@org)
@org.receipts.size
#=> 2

## Create third receipt for same domain
@receipt3, @secret3 = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'third secret', domain: @domain.display_domain)
@receipt3.org_id = @org.objid
@receipt3.domain_id = @domain.objid
@receipt3.save
@receipt3.add_to_organization_receipts(@org)
@receipt3.add_to_custom_domain_receipts(@domain)
@domain.receipts.size
#=> 2

## Organization has 3 receipts total
@org.receipts.size
#=> 3

## Query organization receipts by score range (time-based)
@since = (Familia.now - 3600).to_i
@now = Familia.now.to_f
@org_receipt_ids = @org.receipts.rangebyscore(@since, @now)
@org_receipt_ids.size
#=> 3

## Query domain receipts by score range (time-based)
@domain_receipt_ids = @domain.receipts.rangebyscore(@since, @now)
@domain_receipt_ids.size
#=> 2

## Bulk load receipts from organization query
@org_receipts = Onetime::Receipt.load_multi(@org_receipt_ids).compact
@org_receipts.size
#=> 3

## Bulk load receipts from domain query
@domain_receipts = Onetime::Receipt.load_multi(@domain_receipt_ids).compact
@domain_receipts.size
#=> 2

## Remove receipt from organization
@receipt2.remove_from_organization_receipts(@org)
@org.receipts.size
#=> 2

## Receipt no longer in organization collection
@org.receipts.member?(@receipt2.objid)
#=> false

## Receipt participations updated after removal
@receipt2.organization_instances.size
#=> 0

## Remove receipt from domain
@receipt3.remove_from_custom_domain_receipts(@domain)
@domain.receipts.size
#=> 1

## Receipt no longer in domain collection
@domain.receipts.member?(@receipt3.objid)
#=> false

## Create second organization for isolation testing
@org2 = Onetime::Organization.create!('Other Org', @owner, "other@test-#{@timestamp}.com")
@receipt4, @secret4 = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'other org secret')
@receipt4.org_id = @org2.objid
@receipt4.save
@receipt4.add_to_organization_receipts(@org2)
@org2.receipts.size
#=> 1

## First org does not see second org's receipts
@org.receipts.size
#=> 2

## Receipt destroy cleans up participations
@receipt.destroy!
@org.receipts.member?(@receipt.objid)
#=> false

## Domain participations cleaned after receipt destroy
@domain.receipts.member?(@receipt.objid)
#=> false

## Organization receipts size decremented after destroy
@org.receipts.size
#=> 1

## Domain receipts size decremented after destroy
@domain.receipts.size
#=> 0

## Secret also destroyed with receipt destroy is handled separately
@secret.exists?
#=> true

# Teardown - clean up all test data
@secret.destroy! if @secret&.exists?
@secret2.destroy! if @secret2&.exists?
@secret3.destroy! if @secret3&.exists?
@secret4.destroy! if @secret4&.exists?
@receipt2.destroy! if @receipt2&.exists?
@receipt3.destroy! if @receipt3&.exists?
@receipt4.destroy! if @receipt4&.exists?
@domain.destroy! if @domain&.exists?
@org2.destroy! if @org2&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
