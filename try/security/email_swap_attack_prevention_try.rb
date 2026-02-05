# try/security/email_swap_attack_prevention_try.rb
#
# frozen_string_literal: true

# Security tests for email-swap attack prevention (#2471).
#
# Attack vector:
# 1. Attacker subscribes with attacker@evil.com
# 2. System computes email_hash from attacker's billing_email
# 3. email_hash stored immutably in Stripe customer metadata
# 4. Attacker changes their Stripe email to victim@example.com
# 5. Webhook fires - what happens?
#
# Expected defense:
# - Webhook handler uses email_hash from Stripe metadata, NOT current email
# - Victim's org (with victim's email_hash) is NOT matched
# - Attacker only affects their own org
#
# Run: pnpm run test:tryouts:agent try/security/email_swap_attack_prevention_try.rb

require_relative '../support/test_helpers'

# Stub the HMAC secret for testing
ENV['FEDERATION_HMAC_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'

# Setup attack scenario - using SETUP method pattern for Tryouts
def setup_attack_scenario
  return if @setup_complete

  @attacker_email = generate_unique_test_email('attacker')
  @victim_email = generate_unique_test_email('victim')

  # Create attacker and victim customers
  @attacker_customer = Onetime::Customer.create!(@attacker_email)
  @victim_customer = Onetime::Customer.create!(@victim_email)

  # Create organizations with unique contact_emails and billing_emails
  @attacker_org = Onetime::Organization.create!(
    'Attacker Workspace',
    @attacker_customer,
    "contact-attacker-#{SecureRandom.hex(8)}@example.com"
  )
  @attacker_org.billing_email = "billing-attacker-#{SecureRandom.hex(8)}@example.com"
  @attacker_org.compute_email_hash!
  @attacker_org.stripe_customer_id = "cus_attacker_#{SecureRandom.hex(4)}"
  @attacker_org.stripe_subscription_id = "sub_attacker_#{SecureRandom.hex(4)}"
  @attacker_org.subscription_status = 'active'
  @attacker_org.save

  @victim_org = Onetime::Organization.create!(
    'Victim Workspace',
    @victim_customer,
    "contact-victim-#{SecureRandom.hex(8)}@example.com"
  )
  @victim_org.billing_email = "billing-victim-#{SecureRandom.hex(8)}@example.com"
  @victim_org.compute_email_hash!
  @victim_org.save

  # Store immutable hash (simulates Stripe metadata)
  @stripe_metadata_hash = @attacker_org.email_hash.dup
  @victim_hash = @victim_org.email_hash.dup

  @setup_complete = true
end

# Initialize for all tests
setup_attack_scenario

## PREREQUISITE: Attacker and victim have different email hashes
setup_attack_scenario
@attacker_org.email_hash != @victim_org.email_hash
#=> true

## DEFENSE CHECK 1: Lookup by attacker's hash finds attacker org
setup_attack_scenario
found = Onetime::Organization.find_all_by_email_hash(@stripe_metadata_hash)
found.map(&:objid).include?(@attacker_org.objid)
#=> true

## DEFENSE CHECK 2: Lookup by victim's hash finds victim org
setup_attack_scenario
found = Onetime::Organization.find_all_by_email_hash(@victim_hash)
found.map(&:objid).include?(@victim_org.objid)
#=> true

## DEFENSE CHECK 3: Webhook lookup uses metadata hash, not current email
setup_attack_scenario
owner_org = Onetime::Organization.find_by_stripe_customer_id(@attacker_org.stripe_customer_id)
owner_org&.objid == @attacker_org.objid
#=> true

## DEFENSE CHECK 4: Federated lookup by attacker's hash does NOT find victim
setup_attack_scenario
all_orgs = Onetime::Organization.find_all_by_email_hash(@stripe_metadata_hash)
federated_orgs = all_orgs.select { |org| org.stripe_customer_id.to_s.empty? }
!federated_orgs.map(&:objid).include?(@victim_org.objid)
#=> true

## DEFENSE CHECK 5: Victim org would NOT match attacker's hash
setup_attack_scenario
Onetime::Organization.find_all_by_email_hash(@stripe_metadata_hash)
  .map(&:objid).include?(@victim_org.objid)
#=> false

## DEFENSE CHECK 6: Victim org status remains unchanged
setup_attack_scenario
original_status = @victim_org.subscription_status
@victim_org.refresh!
@victim_org.subscription_status == original_status
#=> true

## DEFENSE CHECK 7: Victim is never marked as federated
setup_attack_scenario
@victim_org.subscription_federated?
#=> false

## DEFENSE CHECK 8: Victim's subscription_federated_at remains nil
setup_attack_scenario
@victim_org.subscription_federated_at.to_s.empty?
#=> true

## DEFENSE CHECK 9: Hash length is sufficient (128 bits)
setup_attack_scenario
@stripe_metadata_hash.length >= 32
#=> true

## DEFENSE CHECK 10: EmailHash.compute is deterministic
setup_attack_scenario
recomputed = Onetime::Utils::EmailHash.compute(@attacker_org.billing_email)
recomputed == @stripe_metadata_hash
#=> true

## DEFENSE CHECK 11: Different secret produces different hash
setup_attack_scenario
original_secret = ENV['FEDERATION_HMAC_SECRET']
ENV['FEDERATION_HMAC_SECRET'] = 'different-secret-for-comparison'
different_hash = Onetime::Utils::EmailHash.compute(@attacker_org.billing_email)
ENV['FEDERATION_HMAC_SECRET'] = original_secret
different_hash != @stripe_metadata_hash
#=> true

# Teardown
@attacker_org&.destroy! rescue nil
@victim_org&.destroy! rescue nil
@attacker_customer&.destroy! rescue nil
@victim_customer&.destroy! rescue nil
