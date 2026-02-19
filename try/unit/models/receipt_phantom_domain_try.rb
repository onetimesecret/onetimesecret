# try/unit/models/receipt_phantom_domain_try.rb
#
# frozen_string_literal: true

# Tests for phantom domain ZSET entries:
# Verifies receipts without domain_id are NOT in any domain ZSET,
# and receipts with domain_id are in exactly the right ZSET.
# Also tests that destroy! cleans up phantom entries via reverse lookup.

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for phantom domain tests'

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "phantom_test_#{@timestamp}@test.com")
@org = Onetime::Organization.create!('Phantom Test Org', @owner, "phantom@test-#{@timestamp}.com")
@domain = Onetime::CustomDomain.create!("phantom-#{@timestamp}.test.com", @org.objid)

## Receipt WITHOUT domain: domain_id should be nil
@receipt_no_domain, @secret_no_domain = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'no domain secret')
@receipt_no_domain.org_id = @org.objid
@receipt_no_domain.save
@receipt_no_domain.add_to_organization_receipts(@org)
@receipt_no_domain.domain_id.nil?
#=> true

## Receipt without domain should NOT appear in domain's receipts ZSET
@domain.receipt?(@receipt_no_domain.objid)
#=> false

## Receipt without domain should have zero custom_domain_instances
@receipt_no_domain.custom_domain_instances.size
#=> 0

## Receipt WITH domain: domain_id should be set
@receipt_with_domain, @secret_with_domain = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'with domain secret', domain: @domain.display_domain)
@receipt_with_domain.org_id = @org.objid
@receipt_with_domain.domain_id = @domain.objid
@receipt_with_domain.save
@receipt_with_domain.add_to_organization_receipts(@org)
@receipt_with_domain.add_to_custom_domain_receipts(@domain)
@receipt_with_domain.domain_id
#=> @domain.objid

## Receipt with domain appears in correct domain ZSET
@domain.receipt?(@receipt_with_domain.objid)
#=> true

## Receipt with domain has exactly 1 custom_domain_instance
@receipt_with_domain.custom_domain_instances.size
#=> 1

## Create second domain for cross-contamination test
@domain2 = Onetime::CustomDomain.create!("other-#{@timestamp}.test.com", @org.objid)
@domain2.is_a?(Onetime::CustomDomain)
#=> true

## Receipt with domain1 should NOT be in domain2's ZSET
@domain2.receipt?(@receipt_with_domain.objid)
#=> false

## Simulate phantom: add receipt to domain ZSET without setting domain_id
@phantom_receipt, @phantom_secret = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'phantom secret')
@phantom_receipt.org_id = @org.objid
@phantom_receipt.save
@phantom_receipt.add_to_organization_receipts(@org)
@phantom_receipt.add_to_custom_domain_receipts(@domain)
@phantom_receipt.domain_id.nil?
#=> true

## Phantom receipt IS in domain ZSET (confirming no guard exists)
@domain.receipt?(@phantom_receipt.objid)
#=> true

## Phantom receipt's custom_domain_instances finds it via reverse lookup
@phantom_receipt.custom_domain_instances.size
#=> 1

## destroy! cleans up phantom ZSET entry via reverse lookup
@phantom_receipt.destroy!
@domain.receipt?(@phantom_receipt.objid)
#=> false

## Destroy receipt with domain_id set verifies ZSET cleanup
@receipt_with_domain.destroy!
@domain.receipt?(@receipt_with_domain.objid)
#=> false

## Domain ZSET should be empty after both domain-linked receipts destroyed
@domain.receipts.size
#=> 0

## Receipt with share_domain but no domain_id stays out of domain ZSET
@receipt_share_only, @secret_share_only = Onetime::Receipt.spawn_pair(@owner.objid, 3600, 'share domain only', domain: @domain.display_domain)
@receipt_share_only.org_id = @org.objid
@receipt_share_only.save
@receipt_share_only.add_to_organization_receipts(@org)
@receipt_share_only.share_domain
#=> @domain.display_domain

## share_domain set but not enrolled in domain ZSET
@domain.receipt?(@receipt_share_only.objid)
#=> false

## domain_id is nil because we never set it
@receipt_share_only.domain_id.nil?
#=> true

# Teardown
@secret_no_domain.destroy! if @secret_no_domain&.exists?
@secret_with_domain.destroy! if @secret_with_domain&.exists?
@phantom_secret.destroy! if @phantom_secret&.exists?
@secret_share_only.destroy! if @secret_share_only&.exists?
@receipt_no_domain.destroy! if @receipt_no_domain&.exists?
@receipt_share_only.destroy! if @receipt_share_only&.exists?
@domain.destroy! if @domain&.exists?
@domain2.destroy! if @domain2&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
