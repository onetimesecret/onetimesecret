# try/unit/models/organization_race_condition_try.rb
#
# frozen_string_literal: true

# Tests for race condition prevention in Organization.create!
#
# Issue #2880: Remove write operations from OrganizationLoader auth phase
#
# These tests verify that concurrent requests to create an organization
# with the same contact_email are handled correctly:
# - Only one organization is created
# - The duplicate request gets an appropriate error
# - Uses unique_index on contact_email for atomic guard
#
# Run: bundle exec try try/unit/models/organization_race_condition_try.rb

require_relative '../../support/test_helpers'
OT.boot! :test

# Setup test data with unique identifiers
@test_suffix = "#{Familia.now.to_i}_#{SecureRandom.hex(6)}"

# Helper to clean stale index entries from previous failed runs
def clean_index_and_org(email)
  return unless email
  org = Onetime::Organization.find_by_contact_email(email)
  org.destroy! if org&.exists?
  Onetime::Organization.contact_email_index.remove(email)
end

# Create test customers
@owner1 = Onetime::Customer.create!(email: "race_owner1_#{@test_suffix}@onetimesecret.com")
@owner2 = Onetime::Customer.create!(email: "race_owner2_#{@test_suffix}@onetimesecret.com")

# Pre-clean test emails to avoid conflicts from previous runs
@unique_email = "unique_test_#{@test_suffix}@onetimesecret.com"
@concurrent_email = "concurrent_#{@test_suffix}@onetimesecret.com"
clean_index_and_org(@unique_email)
clean_index_and_org(@concurrent_email)

# Test nil email organizations first (these don't use unique index)

## Organization.create! allows nil contact_email (multiple orgs can have nil)
@org_nil_email1 = Onetime::Organization.create!(
  "Org Without Email 1",
  @owner1,
  nil
)
@org_nil_email1.contact_email.nil?
#=> true

## Second organization with nil contact_email is allowed
@org_nil_email2 = Onetime::Organization.create!(
  "Org Without Email 2",
  @owner2,
  nil
)
@org_nil_email2.contact_email.nil?
#=> true

## Both nil-email organizations exist independently
[@org_nil_email1.objid != @org_nil_email2.objid, @org_nil_email1.exists?, @org_nil_email2.exists?]
#=> [true, true, true]

## Organization.create! allows empty string contact_email (treated as nil)
@org_empty_email = Onetime::Organization.create!(
  "Org With Empty Email",
  @owner1,
  ""
)
@org_empty_email.contact_email.nil?
#=> true

# Test email uniqueness enforcement

## Organization.create! succeeds for first request with unique contact_email
@org1 = Onetime::Organization.create!(
  "First Org",
  @owner1,
  @unique_email
)
[@org1.class, @org1.contact_email]
#=> [Onetime::Organization, @unique_email]

## contact_email_exists? returns true after creation
Onetime::Organization.contact_email_exists?(@unique_email)
#=> true

## find_by_contact_email returns the created organization
found = Onetime::Organization.find_by_contact_email(@unique_email)
found&.objid == @org1.objid
#=> true

## Organization.create! raises error for duplicate contact_email
begin
  Onetime::Organization.create!(
    "Second Org",
    @owner2,
    @unique_email
  )
  :no_error_raised
rescue Onetime::Problem, Familia::RecordExistsError => e
  e.message.downcase.include?('exists')
end
#=> true

## contact_email_exists? returns false for non-existent email
Onetime::Organization.contact_email_exists?("nonexistent_#{@test_suffix}@example.com")
#=> false

# Test concurrent creation scenario

## Concurrent creation attempts result in exactly one success
concurrent_results = []
concurrent_mutex = Mutex.new
threads = []
2.times do |i|
  owner = i == 0 ? @owner1 : @owner2
  threads << Thread.new do
    begin
      org = Onetime::Organization.create!(
        "Concurrent Org #{i}",
        owner,
        @concurrent_email
      )
      concurrent_mutex.synchronize { concurrent_results << { success: true, org_id: org.objid } }
    rescue Onetime::Problem, Familia::RecordExistsError => e
      concurrent_mutex.synchronize { concurrent_results << { success: false, error: e.message } }
    end
  end
end
threads.each(&:join)
@concurrent_results = concurrent_results
successes = @concurrent_results.count { |r| r[:success] }
failures = @concurrent_results.count { |r| !r[:success] }
[successes, failures]
#=> [1, 1]

## Failed concurrent attempt gets error message containing 'exists'
failed_result = @concurrent_results.find { |r| !r[:success] }
failed_result && failed_result[:error].to_s.downcase.include?('exists')
#=> true

## Successful concurrent creation results in org being findable
@found_org = Onetime::Organization.find_by_contact_email(@concurrent_email)
@found_org.nil? == false
#=> true

# Teardown
@org1&.destroy! if @org1&.respond_to?(:exists?) && @org1&.exists?
@org_nil_email1&.destroy! if @org_nil_email1&.respond_to?(:exists?) && @org_nil_email1&.exists?
@org_nil_email2&.destroy! if @org_nil_email2&.respond_to?(:exists?) && @org_nil_email2&.exists?
@org_empty_email&.destroy! if @org_empty_email&.respond_to?(:exists?) && @org_empty_email&.exists?
@found_org&.destroy! if @found_org&.respond_to?(:exists?) && @found_org&.exists?

clean_index_and_org(@unique_email)
clean_index_and_org(@concurrent_email)

@owner1&.destroy! if @owner1&.respond_to?(:exists?) && @owner1&.exists?
@owner2&.destroy! if @owner2&.respond_to?(:exists?) && @owner2&.exists?
