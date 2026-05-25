# try/unit/models/custom_domain_load_error_handling_try.rb
#
# frozen_string_literal: true

# Tests for CustomDomain.load_by_display_domain error handling.
#
# The method must fail-open (return nil) on any error to allow callers
# to fall back gracefully. This includes:
#   - Redis connectivity errors during display_domains.get()
#   - RecordNotFound when the domain_id exists in index but record is gone
#   - Any unexpected StandardError
#
# Security note: Fail-open here means "treat as no custom domain" which
# falls back to global config. This is acceptable because:
#   1. Per-domain config is optional (global config is the baseline)
#   2. Blocking legitimate requests due to transient Redis errors is worse
#   3. Callers (SignupValidation, DomainStrategy) handle nil gracefully
#
# Run:
#   try try/unit/models/custom_domain_load_error_handling_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for load_by_display_domain error handling test"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@fqdn = "error-test-#{@ts}-#{@entropy}.example.com"
@owner = Onetime::Customer.create!(email: "error_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Error Test Org #{@ts}", @owner, "error_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!(@fqdn, @org.objid)

# --- Normal Operation ---

## load_by_display_domain returns domain for known FQDN
Onetime::CustomDomain.load_by_display_domain(@fqdn).identifier
#=> @domain.identifier

## load_by_display_domain returns nil for unknown FQDN
Onetime::CustomDomain.load_by_display_domain('unknown.example.com')
#=> nil

## load_by_display_domain returns nil for nil input
Onetime::CustomDomain.load_by_display_domain(nil)
#=> nil

## load_by_display_domain returns nil for empty string
Onetime::CustomDomain.load_by_display_domain('')
#=> nil

# --- Orphaned Index Entry (domain_id in index, but record deleted) ---
#
# Simulates data corruption where display_domains hash has a domain_id
# that no longer exists (e.g., manual Redis deletion, partial cleanup).

## Create orphan scenario: manually insert stale index entry
@orphan_fqdn = "orphan-#{@ts}-#{@entropy}.example.com"
@orphan_id = "nonexistent-domain-id-#{@ts}"

## Manually insert stale entry into display_domains index
Onetime::CustomDomain.display_domains.put(@orphan_fqdn, @orphan_id)
Onetime::CustomDomain.display_domains.get(@orphan_fqdn)
#=> @orphan_id

## load_by_display_domain returns nil for orphaned index entry (not crash)
Onetime::CustomDomain.load_by_display_domain(@orphan_fqdn)
#=> nil

# --- SignupValidation Integration ---
#
# Verify that SignupValidation handles nil from load_by_display_domain correctly

## SignupValidation.valid_signup_email? falls back to global when domain not found
OT.conf['site'] ||= {}
OT.conf['site']['authentication'] ||= {}
OT.conf['site']['authentication']['allowed_signup_domains'] = nil
Onetime::SignupValidation.valid_signup_email?('user@any.com', display_domain: 'unknown.example.com')
#=> true

## SignupValidation.valid_signup_email? falls back to global for orphaned domain
Onetime::SignupValidation.valid_signup_email?('user@any.com', display_domain: @orphan_fqdn)
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info "Cleaned Redis after load_by_display_domain error handling test"
