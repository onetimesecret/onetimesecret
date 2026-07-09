# apps/web/auth/spec/integration/full/federated_subscription_verify_hook_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full auth stack)
# =============================================================================
#
# End-to-end coverage for the federated-subscription verification gate as it is
# driven through the REAL Rodauth signup path (Auth::Config.create_account via
# internal_request) with the standard email/password hooks in account.rb.
#
# WHY THIS FILE EXISTS
# --------------------
# apps/web/auth/spec/operations/create_default_workspace_federation_spec.rb unit-
# covers the claim gate by calling CreateDefaultWorkspace directly. What it does
# NOT exercise is the account.rb wiring:
#
#   - after_create_account derives `require_verification` from
#     `Onetime.auth_config.verify_account_enabled?` (account.rb) and passes it
#     into CreateDefaultWorkspace, and
#   - after_verify_account (registered ONLY when verify_account is enabled)
#     re-invokes CreateDefaultWorkspace.claim_pending_federation_for.
#
# The default test config DISABLES verify_account, so the after_verify_account
# hook block is not even registered under a normal boot. These tests drive the
# real create_account hook and pivot the config predicate to prove both the
# verify-enabled (deferred) and verify-disabled (immediate + audit) branches.
#
# WHAT IS AND ISN'T EXERCISED
# ---------------------------
# EXERCISED end-to-end through Rodauth internal_request:
#   - after_create_account -> CreateCustomer -> CreateDefaultWorkspace with the
#     require_verification value account.rb computes from the config predicate.
#   - The Deliverable-1 residual: when verify_account is disabled, the immediate
#     unverified claim happens AND emits the loud security-audit log.
#
# REPLAYED (not fired through Rodauth's verify_account endpoint):
#   - The after_verify_account body. The real Auth::Config is a one-shot Rodauth
#     class configured with verify_account DISABLED at boot (spec/auth.test.yaml),
#     and it cannot be reconfigured in-process (see
#     apps/web/auth/docs/auth-config-one-shot.md). Rather than poison the shared
#     boot for every other spec by force-enabling the feature process-wide, the
#     "after verification" example replays the exact two operations account.rb's
#     after_verify_account performs, in order:
#         SetCustomerVerification(verified: true, rodauth_already_synced: true)
#         CreateDefaultWorkspace.claim_pending_federation_for(verified_customer)
#     A guard example asserts the wiring contract: the after_verify_account hook
#     is only registered when verify_account is enabled.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full (auto-set for specs under integration/full/)
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/web/auth/spec/integration/full/federated_subscription_verify_hook_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'securerandom'

RSpec.describe 'Federated subscription claim through the real signup/verify hooks',
               type: :integration do
  before(:all) do
    require 'auth/operations/create_default_workspace'
    require 'auth/operations/set_customer_verification'
    require 'billing/models/pending_federated_subscription'
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end
  end

  # Federation requires a configured HMAC secret; EmailHash.compute reads it
  # from ENV first (see lib/onetime/utils/email_hash.rb).
  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  # Capture the loud security-audit warnings emitted by CreateDefaultWorkspace
  # without suppressing real logging.
  let(:auth_warnings) { [] }

  before do
    logger = Onetime.get_logger('Auth')
    allow(logger).to receive(:warn).and_wrap_original do |orig, *args|
      auth_warnings << args.first.to_s
      orig.call(*args)
    end
  end

  let(:password) { 'TestPassword123!' }
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each { |org| org.delete! if org&.exists? rescue nil }
    created_customers.each { |cust| cust.delete! if cust&.exists? rescue nil }

    if defined?(@signup_email) && @signup_email
      hash = Onetime::Utils::EmailHash.compute(@signup_email)
      Billing::PendingFederatedSubscription.find_by_email_hash(hash)&.destroy! rescue nil

      row = Auth::Database.connection[:accounts].where(email: @signup_email).first
      if row
        %i[account_verification_keys account_password_hashes accounts].each do |t|
          Auth::Database.connection[t].where(id: row[:id]).delete rescue nil
        end
      end
      Onetime::Customer.find_by_email(@signup_email)&.destroy! rescue nil
    end
  end

  AUDIT_MESSAGE = /SECURITY: federated subscription claimed WITHOUT email verification/

  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(8)}@onetimesecret.com"
  end

  # Simulate a Stripe webhook that arrived before the account existed here.
  def create_pending_for(email, status: 'active', planid: 'pro_monthly')
    hash = Onetime::Utils::EmailHash.compute(email)
    pending = Billing::PendingFederatedSubscription.new(hash)
    pending.subscription_status     = status
    pending.planid                  = planid
    pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
    pending.region                  = 'US'
    pending.received_at             = Time.now.to_i.to_s
    pending.save
    pending
  end

  def pending_exists?(email)
    hash = Onetime::Utils::EmailHash.compute(email)
    !Billing::PendingFederatedSubscription.find_by_email_hash(hash).nil?
  end

  # Drive the REAL standard signup through Rodauth internal_request. This fires
  # the real after_create_account hook (account.rb), which creates the Customer,
  # provisions the default workspace, and applies/defers the federated claim
  # based on the require_verification value it derives from the config predicate.
  def signup_via_rodauth(email)
    Auth::Config.create_account(login: email, password: password)
    Onetime::Customer.find_by_email(email)
  end

  def default_org_for(customer)
    customer.organization_instances.to_a.first
  end

  describe 'verify_account ENABLED: standard signup defers the federated claim' do
    it 'creates the workspace but does NOT claim, then claims once verified' do
      # account.rb computes require_verification from this predicate; force it on
      # so the real signup hook takes the verify-enabled (deferred) branch.
      allow(Onetime.auth_config).to receive(:verify_account_enabled?).and_return(true)

      @signup_email = unique_email('verify-enabled')
      create_pending_for(@signup_email)

      customer = signup_via_rodauth(@signup_email)
      created_customers << customer
      expect(customer).to be_a(Onetime::Customer)
      expect(customer.verified?).to be(false)

      org = default_org_for(customer)
      created_organizations << org

      # Workspace provisioned at signup...
      expect(org).to be_a(Onetime::Organization)
      expect(org.is_default).to be(true)

      # ...but the federated subscription is deferred, not claimed.
      expect(org.subscription_federated?).to be(false)
      expect(org.subscription_status.to_s).to eq('')
      expect(pending_exists?(@signup_email)).to be(true)

      # No unverified-claim audit log on the deferred path.
      expect(auth_warnings).not_to include(a_string_matching(AUDIT_MESSAGE))

      # Now replay exactly what account.rb's after_verify_account hook does once
      # the user proves email ownership: mark verified, then re-run the claim.
      Auth::Operations::SetCustomerVerification.new(
        customer: customer,
        verified: true,
        verified_by: 'email',
        rodauth_already_synced: true,
      ).call

      verified_customer = Onetime::Customer.find_by_extid(customer.extid)
      applied = Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(verified_customer)
      expect(applied).to be(true)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(org.planid.to_s).to eq('pro_monthly')
      expect(pending_exists?(@signup_email)).to be(false)
    end
  end

  describe 'verify_account DISABLED: standard signup claims immediately with an audit log' do
    it 'claims at signup (residual) and emits the loud security-audit warning' do
      # Mirror a deployment that turned email verification OFF. account.rb then
      # passes require_verification: false and the claim runs immediately, with
      # no proof of email ownership — the residual this branch documents.
      allow(Onetime.auth_config).to receive(:verify_account_enabled?).and_return(false)

      @signup_email = unique_email('verify-disabled')
      create_pending_for(@signup_email)

      customer = signup_via_rodauth(@signup_email)
      created_customers << customer
      expect(customer.verified?).to be(false)

      org = default_org_for(customer)
      created_organizations << org

      # The benefit is claimed immediately despite no verification.
      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(pending_exists?(@signup_email)).to be(false)

      # And the residual is made visible: a loud, structured audit warning.
      expect(auth_warnings).to include(a_string_matching(AUDIT_MESSAGE))
    end
  end

  describe 'after_verify_account wiring contract' do
    it 'registers the verify-account hook only when the feature is enabled' do
      # The real Auth::Config booted with verify_account disabled (test default),
      # so Rodauth never enabled the feature and the after_verify_account hook in
      # account.rb was never registered. internal_request only exposes a method
      # per enabled route, so the absence of :verify_account proves the gate.
      # This is exactly why the deferred claim must be re-driven from that hook
      # (replayed above) when verify_account IS enabled.
      expect(Onetime.auth_config.verify_account_enabled?).to be(false)
      expect(Auth::Config.respond_to?(:verify_account)).to be(false)
    end
  end
end
