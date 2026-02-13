# try/unit/models/migration_fields_try.rb
#
# frozen_string_literal: true

# Tests for WithMigrationFields feature, specifically verifying:
# 1. _original_object responds as a Familia hashkey (not a jsonkey)
# 2. hgetall returns stored fields
# 3. Old _original_record jsonkey is no longer present

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "mf_owner_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("MF Test Org", @owner, "mf_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("mf-test.example.com", @org.objid)

## CustomDomain responds to _original_object (hashkey accessor)
@domain.respond_to?(:_original_object)
#=> true

## _original_object is a Familia::HashKey
@domain._original_object.class
#=> Familia::HashKey

## _original_object supports hgetall
@domain._original_object.respond_to?(:hgetall)
#=> true

## _original_object starts empty for newly created domains
@domain._original_object.hgetall
#=> {}

## original_record returns nil when _original_object is empty
@domain.original_record
#=> nil

## original_object alias also returns nil when empty
@domain.original_object
#=> nil

## original_record? returns false when no original data stored
@domain.original_record?
#=> false

## Can store data in _original_object hashkey
@domain._original_object['custid'] = 'test_custid_123'
@domain._original_object['display_domain'] = 'mf-test.example.com'
@domain._original_object['created'] = '1700000000'
@stored = @domain._original_object.hgetall
@stored.key?('custid')
#=> true

## hgetall returns all stored fields
@stored.keys.sort
#=> ["created", "custid", "display_domain"]

## Field values are preserved correctly
@stored['custid']
#=> "test_custid_123"

## original_record returns the hash when data is present
@domain.original_record.is_a?(Hash)
#=> true

## original_record? returns true when data is stored
@domain.original_record?
#=> true

## Old _original_record jsonkey is NOT present on CustomDomain
@domain.respond_to?(:_original_record)
#=> false

## Customer also has _original_object as hashkey (not jsonkey)
@owner._original_object.class
#=> Familia::HashKey

## Customer does not have old _original_record
@owner.respond_to?(:_original_record)
#=> false

## Organization also has _original_object as hashkey
@org._original_object.class
#=> Familia::HashKey

## Organization does not have old _original_record
@org.respond_to?(:_original_record)
#=> false

## Secret model has _original_object as hashkey
@secret = Onetime::Secret.new
@secret.respond_to?(:_original_object)
#=> true

## Secret _original_object is a Familia::HashKey
@secret._original_object.class
#=> Familia::HashKey

## Secret does not have old _original_record
@secret.respond_to?(:_original_record)
#=> false

## CustomDomain responds to _original_brand (custom_domain_migration_fields hashkey)
@domain.respond_to?(:_original_brand)
#=> true

## _original_brand is a Familia::HashKey
@domain._original_brand.class
#=> Familia::HashKey

## CustomDomain responds to _original_logo (custom_domain_migration_fields hashkey)
@domain.respond_to?(:_original_logo)
#=> true

## _original_logo is a Familia::HashKey
@domain._original_logo.class
#=> Familia::HashKey

## CustomDomain responds to _original_icon (custom_domain_migration_fields hashkey)
@domain.respond_to?(:_original_icon)
#=> true

## _original_icon is a Familia::HashKey
@domain._original_icon.class
#=> Familia::HashKey

## _original_brand starts empty for newly created domains
@domain._original_brand.hgetall
#=> {}

## Can store data in _original_brand hashkey
@domain._original_brand['primary_color'] = '#dc4a22'
@domain._original_brand['font_family'] = 'Inter'
@domain._original_brand.hgetall.key?('primary_color')
#=> true

## _original_brand data persists in Redis
@domain._original_brand['primary_color']
#=> "#dc4a22"

## Customer does NOT have _original_brand (CustomDomain-specific)
@owner.respond_to?(:_original_brand)
#=> false

## Organization does NOT have _original_brand (CustomDomain-specific)
@org.respond_to?(:_original_brand)
#=> false

# Teardown
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
