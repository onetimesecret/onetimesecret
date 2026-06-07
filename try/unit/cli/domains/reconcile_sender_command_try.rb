# try/unit/cli/domains/reconcile_sender_command_try.rb
#
# frozen_string_literal: true

# Tests for DomainsReconcileSenderCommand CLI
#
# Covers:
#   1. Domain not found -> prints error, returns early
#   2. No from_address available -> prints error, returns early
#   3. Dry-run with --from-address, no existing config -> prints plan, no config created
#   4. Dry-run with existing config -> prints plan with "provision with existing config"
#   5. Provision success path -> creates MailerConfig, prints "provisioned successfully"
#   6. Provision failure path -> prints "failed:"
#   7. Non-lettermint existing config -> reconciles without provider refusal
#   8. --provider conflicting with existing config -> refuses to switch
#   9. Unresolvable/invalid provider -> errors, creates no config
#
# Run:
#   try try/unit/cli/domains/reconcile_sender_command_try.rb --agent

require_relative '../../../support/test_models'
require 'securerandom'
require 'stringio'

OT.boot! :test

# Load the CLI command
require 'onetime/cli'
require 'api/domains/cli/helpers'
require 'api/domains/cli/reconcile_sender_command'
require 'onetime/operations/provision_sender_domain'

Familia.dbclient.flushdb
OT.info "Cleaned Redis for ReconcileSenderCommand test run"

@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- Test fixtures ---

@owner = Onetime::Customer.create!(email: "rsc_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("RSC Org #{@timestamp}", @owner, "rsc_#{@timestamp}@test.com")

# Helper to capture stdout from a command invocation
def capture_stdout
  captured = StringIO.new
  old_stdout = $stdout
  $stdout = captured
  yield
  $stdout = old_stdout
  captured.string
ensure
  $stdout = old_stdout
end

# Helper to build a command instance with boot_application! stubbed out
def build_cmd
  cmd = Onetime::CLI::DomainsReconcileSenderCommand.new
  cmd.define_singleton_method(:boot_application!) { nil }
  cmd
end

# Holder module for canned results -- accessible from class reopening blocks
# and across ## test boundaries (constants are global).
module PSDTestData
  class << self
    attr_accessor :canned_result
  end
end

# Patch ProvisionSenderDomain to return canned result from PSDTestData.
# Uses prepend so `super` chains to the original `call` method — a class
# reopen would lose the original and `super` would hit Object (NoMethodError).
module PSDCallStub
  def call
    canned = PSDTestData.canned_result
    return canned if canned

    super
  end
end
Onetime::Operations::ProvisionSenderDomain.prepend(PSDCallStub)


# ===================================================================
# Case 1: Domain not found
# ===================================================================

## Prints error when domain is not found
@output_1 = capture_stdout do
  build_cmd.call(domain_name: "nonexistent-#{@timestamp}.example.com")
end
@output_1.include?('not found')
#=> true

# ===================================================================
# Case 2: No from_address available
# ===================================================================

## Prints error when no from_address and no existing config
@domain_2 = Onetime::CustomDomain.create!("rsc-nofrom-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@output_2 = capture_stdout do
  build_cmd.call(domain_name: @domain_2.display_domain)
end
@output_2.include?('No from_address available')
#=> true

# ===================================================================
# Case 3: Dry-run with --from-address, no existing config
# ===================================================================

## Dry-run prints plan without creating MailerConfig
@domain_3 = Onetime::CustomDomain.create!("rsc-dry3-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@output_3 = capture_stdout do
  build_cmd.call(
    domain_name: @domain_3.display_domain,
    from_address: "noreply@rsc-dry3-#{@timestamp}.example.com",
    provider: 'lettermint',
    dry_run: true,
  )
end
@output_3.include?('[dry-run]')
#=> true

## Dry-run output mentions "create new config, then provision"
@output_3.include?('create new config, then provision')
#=> true

## Dry-run does not create MailerConfig
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_3.identifier)
#=> false

# ===================================================================
# Case 4: Dry-run with existing config
# ===================================================================

## Dry-run with existing config shows "provision with existing config"
@domain_4 = Onetime::CustomDomain.create!("rsc-dry4-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_4 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_4.identifier,
  from_address: "noreply@rsc-dry4-#{@timestamp}.example.com",
  provider: 'lettermint',
)
@output_4 = capture_stdout do
  build_cmd.call(
    domain_name: @domain_4.display_domain,
    dry_run: true,
  )
end
@output_4.include?('provision with existing config')
#=> true

## Dry-run with existing config uses its from_address
@output_4.include?("noreply@rsc-dry4-#{@timestamp}.example.com")
#=> true

# ===================================================================
# Case 5: Provision success path
# ===================================================================

## Successful provision creates MailerConfig and prints success
@domain_5 = Onetime::CustomDomain.create!("rsc-ok-#{@timestamp}-#{@entropy}.example.com", @org.objid)
PSDTestData.canned_result = Onetime::Operations::ProvisionSenderDomain::Result.new(
  success: true,
  dns_records: [
    { 'type' => 'CNAME', 'name' => 'lm1._domainkey.example.com', 'value' => 'lm1.dkim.lettermint.com' },
  ],
  provider_data: { 'status' => 'pending' },
  error: nil,
)
@output_5 = capture_stdout do
  build_cmd.call(
    domain_name: @domain_5.display_domain,
    from_address: "noreply@rsc-ok-#{@timestamp}.example.com",
    provider: 'lettermint',
  )
end
@output_5.include?('provisioned successfully')
#=> true

## MailerConfig was created for the domain
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_5.identifier)
#=> true

## Created MailerConfig has provider 'lettermint'
@mc_5 = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain_5.identifier)
@mc_5.provider
#=> 'lettermint'

## Created MailerConfig has sending_mode 'platform'
@mc_5.sending_mode
#=> 'platform'

## Created MailerConfig is not enabled
@mc_5.enabled?
#=> false

# ===================================================================
# Case 6: Provision failure path
# ===================================================================

## Failed provision prints failure message
@domain_6 = Onetime::CustomDomain.create!("rsc-fail-#{@timestamp}-#{@entropy}.example.com", @org.objid)
PSDTestData.canned_result = Onetime::Operations::ProvisionSenderDomain::Result.new(
  success: false,
  dns_records: [],
  provider_data: nil,
  error: 'Lettermint API rate limit exceeded',
)
@output_6 = capture_stdout do
  build_cmd.call(
    domain_name: @domain_6.display_domain,
    from_address: "noreply@rsc-fail-#{@timestamp}.example.com",
    provider: 'lettermint',
  )
end
@output_6.include?('failed:')
#=> true

## Failure output includes the error message
@output_6.include?('Lettermint API rate limit exceeded')
#=> true

# ===================================================================
# Case 7: Non-lettermint existing config -> reconciles, no refusal
# ===================================================================

## Existing ses config reconciles without the provider-mismatch refusal
@domain_7 = Onetime::CustomDomain.create!("rsc-ses-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_7 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_7.identifier,
  from_address: "noreply@rsc-ses-#{@timestamp}.example.com",
  provider: 'ses',
)
PSDTestData.canned_result = Onetime::Operations::ProvisionSenderDomain::Result.new(
  success: true,
  dns_records: [],
  provider_data: { 'status' => 'pending' },
  error: nil,
)
@output_7 = capture_stdout do
  build_cmd.call(domain_name: @domain_7.display_domain)
end
@output_7.include?('provisioned successfully')
#=> true

## Reconcile output reflects the ses provider, not lettermint
@output_7.include?('provider: ses')
#=> true

## No provider-mismatch refusal for the existing ses config
@output_7.include?('Delete the existing sender config first')
#=> false

# ===================================================================
# Case 8: --provider conflicting with existing config -> refuses switch
# ===================================================================

## --provider that differs from existing config refuses to switch
@output_8 = capture_stdout do
  build_cmd.call(domain_name: @domain_7.display_domain, provider: 'sendgrid')
end
@output_8.include?('Delete the existing sender config first')
#=> true

# ===================================================================
# Case 9: Unresolvable/invalid provider -> errors, creates no config
# ===================================================================
# In the test environment the installation default sender provider is
# 'logger', which is not a valid MailerConfig provider. With no --provider
# and no existing config, the command should refuse rather than create an
# invalid config.

## No valid provider resolvable -> prints error
@domain_9 = Onetime::CustomDomain.create!("rsc-noprov-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@output_9 = capture_stdout do
  build_cmd.call(
    domain_name: @domain_9.display_domain,
    from_address: "noreply@rsc-noprov-#{@timestamp}.example.com",
  )
end
@output_9.include?('Could not resolve a valid sender provider')
#=> true

## No MailerConfig is created when the provider is unresolvable
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_9.identifier)
#=> false

# --- Cleanup ---
PSDTestData.canned_result = nil
Familia.dbclient.flushdb
OT.info "Cleaned Redis after ReconcileSenderCommand test run"
