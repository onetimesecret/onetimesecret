# apps/web/auth/spec/operations/ensure_default_workspace_federation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Security regression tests for the pending-federated-subscription claim gate
# in Auth::Operations::EnsureDefaultWorkspace.
#
# Background
# ----------
# Stripe webhooks fan out to every region. When a checkout completes but no
# local org matches the account's email hash, the region stores a
# PendingFederatedSubscription keyed by HMAC email_hash. Later, when a user
# creates an account in that region, the pending record is claimed and applied.
#
# The gap these tests lock down: on the STANDARD email/password signup path the
# claim used to run from after_create_account, BEFORE the user proved ownership
# of the email. An attacker who knew a paying subscriber's email could register
# it in another region and steal (and destroy) the victim's pending
# subscription at account-creation time.
#
# The fix defers the claim on that path until the email is verified
# (require_verification: true), and re-invokes it through
# EnsureDefaultWorkspace.claim_pending_federation_for once SetCustomerVerification
# stamps a mailbox-proof provenance (after_verify_account, colonel admin, CLI).
# Mailbox-proven callers (invite, post-payment billing, authenticated lazy
# creation) use the default (require_verification: false) and claim immediately.
#
# #4735: the SSO JIT caller is NOT pre-verified in the sense that matters. The
# IdP asserted the address (verified_by: 'sso'); nobody proved mailbox control.
# That caller now passes require_verification: true, and the operation defers
# for an sso_jit record on EVERY path, so a later lazy creation cannot deliver
# the benefit the JIT path withheld. Only Customer#mailbox_verified? (an
# 'email'/'invite_token'/'cli_provision'/'colonel_admin' stamp) lets it through.
#
# #4754 review, F1: the same record-based deferral covers an UNVERIFIED
# standard signup while the deployment has a verification step
# (Customer#federation_claim_deferred?). The callers that pass the default flag
# (the customers doctor's repair, lazy creation, the billing self-heal) used to
# fall through to an immediate claim for such a record. verify_account is off
# under RACK_ENV=test, so those examples stub the config predicate.
#
# #4754 review, round 3: in simple auth mode the redeemed verification link is
# a re-claim trigger too (SetCustomerVerification.record_mailbox_proof). The
# link proves only the mailbox it was sent to, while the claim hashes the
# workspace's billing address, which the owner can change without proving it,
# and an operator email change points the default workspace at the new
# address while links sent to the earlier one stay live. So the claim the link
# runs needs a link on record as sent to the account's current address
# (Secret#delivered_to?) and applies only a pending record for that address
# (own_address_only).
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=full
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/web/auth/spec/operations/ensure_default_workspace_federation_spec.rb
#
# =============================================================================

require 'spec_helper'
require 'securerandom'

RSpec.describe 'EnsureDefaultWorkspace: federated subscription claim gate', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/ensure_default_workspace'
    require 'auth/operations/customers/change_email'
    require 'billing/models/pending_federated_subscription'
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

  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_pending_records) { [] }
  let(:created_links) { [] }

  after do
    created_organizations.each { |org| org.delete! if org&.exists? rescue nil }
    created_customers.each { |cust| cust.delete! if cust&.exists? rescue nil }
    created_pending_records.each { |rec| rec.destroy! rescue nil }
    created_links.each { |obj| obj.destroy! rescue nil }
  end

  def unique_email(prefix = 'fed')
    "#{prefix}-#{SecureRandom.hex(8)}@federation-test.example.com"
  end

  def create_customer(email:, verified:, verified_by: nil, provisioning_origin: nil)
    cust = Onetime::Customer.create!(
      email: email, role: 'customer', verified: verified,
      verified_by: verified ? verified_by : nil, provisioning_origin: provisioning_origin,
    )
    created_customers << cust
    cust
  end

  # Simulate a Stripe webhook that arrived before the account existed here.
  def create_pending_for(email, status: 'active', planid: 'pro_monthly', received_at: Time.now.to_i)
    hash = Onetime::Utils::EmailHash.compute(email)
    pending = Billing::PendingFederatedSubscription.new(hash)
    pending.subscription_status     = status
    pending.planid                  = planid
    pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
    pending.region                  = 'US'
    pending.received_at             = received_at.to_s
    pending.save
    created_pending_records << pending
    pending
  end

  def pending_exists?(email)
    hash = Onetime::Utils::EmailHash.compute(email)
    !Billing::PendingFederatedSubscription.find_by_email_hash(hash).nil?
  end

  # ---------------------------------------------------------------------------
  # Standard (unverified) signup: claim must be DEFERRED
  # ---------------------------------------------------------------------------
  describe 'standard signup before email verification (require_verification: true)' do
    it 'creates the workspace but does NOT claim or destroy the pending record' do
      email = unique_email('standard-unverified')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call

      org = result[:organization]
      created_organizations << org

      # Workspace itself is still provisioned at signup...
      expect(org).to be_a(Onetime::Organization)
      expect(org.is_default).to be true

      # ...but the federated subscription is NOT claimed.
      expect(org.subscription_federated?).to be(false)
      expect(org.subscription_status.to_s).to eq('')

      # And crucially the victim's pending record survives (not stolen).
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # After verification: the deferred claim is applied
  # ---------------------------------------------------------------------------
  describe 'after the standard signup verifies their email' do
    it 'claims and applies the pending subscription, then consumes the record' do
      email = unique_email('standard-verify')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)

      # Signup: workspace created, claim deferred.
      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)

      # Verification happens (mirrors after_verify_account stamping the
      # mailbox-proof 'email' provenance before re-invoking the claim).
      customer.verified    = true
      customer.verified_by = 'email'
      customer.save

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(true)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(org.planid.to_s).to eq('pro_monthly')

      # Pending record consumed exactly once.
      expect(pending_exists?(email)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # The redeemed verification link claims only for the address it proved
  # ---------------------------------------------------------------------------
  # In simple auth mode the v1 and v2 secret reveal logic stamp 'email'
  # through SetCustomerVerification.record_mailbox_proof, whose #call runs this
  # claim (#4754 review, round 3). Following the link proves the mailbox it
  # was sent to. The claim hashes the workspace's billing email (else its
  # contact email), which the owner sets through PUT /api/organizations/:extid
  # without proving it, so a workspace pointed at another address must not
  # collect that address's pending subscription. And a link is tied to the
  # account, not to an address, so one sent before an operator changed the
  # address must not collect the new address's either.
  describe 'the claim run by a redeemed verification link' do
    let(:auth_infos) { [] }
    let(:refusal_message) { /claim refused: the workspace bills an address the verification did not prove/ }

    before do
      allow(Onetime.auth_config).to receive(:mode).and_return('simple')
      logger = Onetime.get_logger('Auth')
      allow(logger).to receive(:info).and_wrap_original do |orig, *args|
        auth_infos << args.first.to_s
        orig.call(*args)
      end
    end

    def deferred_signup_workspace(customer)
      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer, require_verification: true).call[:organization]
      created_organizations << org
      org
    end

    # What UpdateOrganization#process writes for a new billing email.
    def change_billing_email(org, address)
      org.billing_email = address
      org.contact_email = address
      org.save
    end

    # A welcome link as send_verification_email mints it: receipt-backed,
    # kind account_verification, and the digest of the address it is emailed
    # to. address: nil gives a link minted before the digest was recorded.
    def welcome_link_for(customer, address: customer.email)
      receipt, secret        = Onetime::Receipt.spawn_pair(customer.objid, 24 * 24 * 60 * 60, 'fortune')
      secret.verification    = true
      secret.kind            = 'account_verification'
      secret.custid          = customer.custid
      secret.delivery_digest = Onetime::Secret.delivery_digest_for(address)
      secret.save
      created_links << receipt << secret
      secret
    end

    # What `bin/ots customers change-email` does without --keep-verified:
    # the address moves, verification is reset and the default workspace's
    # contact email follows the new address.
    def operator_change_email(customer, address)
      result = Auth::Operations::Customers::ChangeEmail.new(
        customer: customer, new_email: address, actor: 'cli', dry_run: false,
        require_verification: true, revoke_sessions: false, notify: false
      ).call
      expect(result.status).to eq(:success)
      Onetime::Customer.load(customer.objid)
    end

    # What the reveal sites call once the link is mailbox proof.
    def redeem(customer, link = welcome_link_for(customer))
      Auth::Operations::SetCustomerVerification.record_mailbox_proof(customer, link)
    end

    it "applies a pending subscription for the account's own address" do
      email = unique_email('link-own')
      create_pending_for(email, planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)
      org = deferred_signup_workspace(customer)
      expect(pending_exists?(email)).to be(true)

      expect(redeem(customer)).to eq(:success)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.planid.to_s).to eq('pro_monthly')
      expect(pending_exists?(email)).to be(false)
      expect(auth_infos).not_to include(a_string_matching(refusal_message))
    end

    it 'applies it when the billing email is the same address in another case' do
      email = unique_email('link-own-case')
      create_pending_for(email, planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)
      org = deferred_signup_workspace(customer)
      change_billing_email(org, email.upcase)

      redeem(customer)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)
    end

    it 'leaves the pending record of a billing email the link did not prove' do
      email  = unique_email('link-attacker')
      victim = unique_email('link-victim')
      create_pending_for(victim, planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)
      org = deferred_signup_workspace(customer)
      change_billing_email(org, victim)

      # The stamp is still recorded; only the claim is withheld.
      expect(redeem(customer)).to eq(:success)
      expect(Onetime::Customer.load(customer.objid).verified_by).to eq('email')

      org.refresh!
      expect(org.subscription_federated?).to be(false)
      expect(org.planid.to_s).not_to eq('pro_monthly')
      expect(pending_exists?(victim)).to be(true)
      expect(auth_infos).to include(a_string_matching(refusal_message))
    end

    # A welcome link still live after the owner gained mailbox proof, revealed
    # through ShowSecret's anonymous branch, reaches the stamp again, and the
    # :no_change repeat retries the claim with whatever billing email the
    # workspace holds by then.
    it 'leaves it on the repeat an already verified owner can trigger' do
      email  = unique_email('link-repeat')
      victim = unique_email('link-repeat-victim')
      customer = create_customer(email: email, verified: true, verified_by: 'email')
      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
      created_organizations << org
      change_billing_email(org, victim)
      create_pending_for(victim)

      expect(redeem(customer)).to eq(:no_change)

      org.refresh!
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(victim)).to be(true)
    end

    # The address is checked once, before the federation lock. A billing
    # email change that lands after the check is caught under the lock, where
    # the claim re-reads the workspace and gives up when the hash it would
    # claim is no longer the one it checked.
    it 'leaves it when the billing email moves to another address after the check' do
      email  = unique_email('link-race')
      victim = unique_email('link-race-victim')
      create_pending_for(victim)
      customer = create_customer(email: email, verified: false)
      org = deferred_signup_workspace(customer)
      allow(Billing::PendingFederatedSubscription).to receive(:with_federation_lock)
        .and_wrap_original do |original, *args, **kwargs, &block|
          change_billing_email(Onetime::Organization.load(org.objid), victim)
          original.call(*args, **kwargs, &block)
        end

      redeem(customer)

      expect(Billing::PendingFederatedSubscription).to have_received(:with_federation_lock)
      org.refresh!
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(victim)).to be(true)
    end

    # The operator change rewrites the workspace's contact email, which the
    # claim hashes, to the new address, and leaves the link sent to the
    # earlier address live. The link proved the earlier mailbox only: it
    # stamps as the direct stamp did, and the new address's record stays.
    it 'leaves the new address record when an operator changed the address after the link was sent' do
      earlier  = unique_email('link-moved-from')
      current  = unique_email('link-moved-to')
      create_pending_for(current, planid: 'pro_monthly')
      customer = create_customer(email: earlier, verified: false)
      org      = deferred_signup_workspace(customer)
      link     = welcome_link_for(customer)
      moved    = operator_change_email(customer, current)
      expect(moved.verified?).to be(false)

      expect(redeem(moved, link)).to eq(:success)
      expect(Onetime::Customer.load(customer.objid).verified_by).to eq('email')

      org.refresh!
      expect(org.contact_email).to eq(current)
      expect(org.subscription_federated?).to be(false)
      expect(org.planid.to_s).not_to eq('pro_monthly')
      expect(pending_exists?(current)).to be(true)
      expect(auth_infos).to include(a_string_matching(/not on record as sent to the account's current address/))
    end

    # The control for the example above: a link sent to the new address
    # proves it, so the same state applies the record.
    it 'applies the new address record for a link sent to the new address' do
      earlier  = unique_email('link-resent-from')
      current  = unique_email('link-resent-to')
      create_pending_for(current, planid: 'pro_monthly')
      customer = create_customer(email: earlier, verified: false)
      org      = deferred_signup_workspace(customer)
      moved    = operator_change_email(customer, current)

      expect(redeem(moved)).to eq(:success)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.planid.to_s).to eq('pro_monthly')
      expect(pending_exists?(current)).to be(false)
    end

    # Minted before the delivery address was recorded: nothing says which
    # mailbox it proves, so it stamps and claims nothing, even for the
    # account's own address. The old direct stamp never claimed either.
    it 'leaves the record for a link that recorded no delivery address' do
      email = unique_email('link-unrecorded')
      create_pending_for(email, planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)
      org = deferred_signup_workspace(customer)
      link = welcome_link_for(customer, address: nil)
      expect(link.delivery_digest).to be_nil

      expect(redeem(customer, link)).to eq(:success)
      expect(Onetime::Customer.load(customer.objid).verified_by).to eq('email')

      org.refresh!
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Default-flag callers cannot claim for an unverified signup (#4754, F1)
  # ---------------------------------------------------------------------------
  describe 'an unverified standard signup reached with the default flag (the doctor repair path)' do
    # Capture the audit warning EnsureDefaultWorkspace emits for the
    # verify-disabled residual, without suppressing real logging.
    let(:auth_warnings) { [] }
    let(:audit_message) { /SECURITY: federated subscription claimed WITHOUT email verification/ }

    before do
      logger = Onetime.get_logger('Auth')
      allow(logger).to receive(:warn).and_wrap_original do |orig, *args|
        auth_warnings << args.first.to_s
        orig.call(*args)
      end
    end

    def unverified_signup(email)
      create_customer(email: email, verified: false, provisioning_origin: 'canonical_signup')
    end

    context 'when the deployment has a verification step' do
      before { allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(true) }

      # bin/ots customers doctor --repair converges a missing or collided
      # default workspace through EnsureDefaultWorkspace.new(customer:).call,
      # with no require_verification flag. The record's own rule must defer
      # the claim for it, exactly as the signup hook's flag did.
      it 'creates the workspace, leaves the pending record unclaimed and logs no audit warning' do
        email = unique_email('doctor-unverified')
        create_pending_for(email)
        customer = unverified_signup(email)
        expect(customer.federation_claim_deferred?).to be(true)

        result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
        org = result[:organization]
        created_organizations << org

        expect(org).to be_a(Onetime::Organization)
        expect(org.is_default).to be true
        expect(org.subscription_federated?).to be(false)
        expect(org.subscription_status.to_s).to eq('')
        expect(pending_exists?(email)).to be(true)
        expect(auth_warnings).not_to include(a_string_matching(audit_message))
      end

      it 'does not claim through the re-claim entry point either while unverified' do
        email = unique_email('doctor-reclaim-unverified')
        create_pending_for(email)
        customer = unverified_signup(email)
        created_organizations << Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]

        expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)).to be(false)
        expect(pending_exists?(email)).to be(true)
      end

      it 'claims once the verification step stamps mailbox proof (after_verify_account)' do
        email = unique_email('doctor-then-verified')
        create_pending_for(email, status: 'active', planid: 'pro_monthly')
        customer = unverified_signup(email)
        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        created_organizations << org
        expect(pending_exists?(email)).to be(true)

        # after_verify_account: Rodauth has committed the Verified row; the
        # hook stamps 'email' and re-invokes the claim through this op.
        outcome = Auth::Operations::SetCustomerVerification.new(
          customer: customer, verified: true, verified_by: 'email', rodauth_already_synced: true,
        ).call
        expect(outcome).to eq(:success)
        expect(customer.federation_claim_deferred?).to be(false)

        org.refresh!
        expect(org.subscription_federated?).to be(true)
        expect(org.planid.to_s).to eq('pro_monthly')
        expect(pending_exists?(email)).to be(false)
      end

      # The predicate deliberately leaves these alone: Rodauth never
      # re-verifies a Verified row, so deferring would strand the plan until
      # an operator stamped it, with no attacker path to the stamp.
      it 'still claims for a verified record with a non-mailbox provenance (autoverify)' do
        email = unique_email('autoverify-immediate')
        create_pending_for(email)
        customer = create_customer(email: email, verified: true, verified_by: 'autoverify')
        expect(customer.mailbox_verified?).to be(false)
        expect(customer.federation_claim_deferred?).to be(false)

        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        created_organizations << org

        expect(org.subscription_federated?).to be(true)
        expect(pending_exists?(email)).to be(false)
      end
    end

    context 'when the deployment has no verification step (the documented residual)' do
      before { allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(false) }

      it 'claims immediately and emits the security-audit warning' do
        email = unique_email('residual-unverified')
        create_pending_for(email)
        customer = unverified_signup(email)
        expect(customer.federation_claim_deferred?).to be(false)

        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        created_organizations << org

        expect(org.subscription_federated?).to be(true)
        expect(org.subscription_status.to_s).to eq('active')
        expect(pending_exists?(email)).to be(false)
        expect(auth_warnings).to include(a_string_matching(audit_message))
      end
    end

    context 'when the auth config cannot be read' do
      before { allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_raise(RuntimeError, 'config unreadable') }

      it 'fails closed: creates the workspace and leaves the pending record' do
        email = unique_email('config-unreadable')
        create_pending_for(email)
        customer = unverified_signup(email)

        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        created_organizations << org

        expect(org).to be_a(Onetime::Organization)
        expect(org.subscription_federated?).to be(false)
        expect(pending_exists?(email)).to be(true)
      end
    end

    context 'when the process resolved simple mode by default' do
      # A bin/ots shell (customers doctor --repair, billing webhooks replay)
      # or a worker container without AUTHENTICATION_MODE resolves simple
      # mode on a full-mode install and reads verify_account_loaded? as
      # false with nothing raised. The record rule fails closed on the
      # unsettled mode instead of reading the verification step as absent
      # and claiming (#4754 review, F1 follow-up).
      before { allow(Onetime.auth_config).to receive_messages(simple_by_default?: true, verify_account_loaded?: false) }

      it 'fails closed: creates the workspace, leaves the pending record and warns instead of claiming' do
        email = unique_email('mode-unsettled')
        create_pending_for(email)
        customer = unverified_signup(email)
        expect(customer.federation_claim_deferred?).to be(true)

        org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        created_organizations << org

        expect(org).to be_a(Onetime::Organization)
        expect(org.subscription_federated?).to be(false)
        expect(pending_exists?(email)).to be(true)
        expect(auth_warnings).to include(a_string_matching(/AUTHENTICATION_MODE/))
        expect(auth_warnings).not_to include(a_string_matching(audit_message))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-verified callers claim immediately (no regression)
  # ---------------------------------------------------------------------------
  describe 'pre-verified callers claim immediately' do
    it 'claims at creation for an already-verified customer (invite path)' do
      email = unique_email('verified-immediate')
      create_pending_for(email)
      customer = create_customer(email: email, verified: true, verified_by: 'invite_token')

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(pending_exists?(email)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # SSO JIT (#4735): an IdP-asserted address is not mailbox proof
  # ---------------------------------------------------------------------------
  describe 'an SSO JIT-provisioned customer (verified_by: sso)' do
    def sso_customer(email)
      create_customer(email: email, verified: true, verified_by: 'sso', provisioning_origin: 'sso_jit')
    end

    it 'does not claim at creation when the JIT caller passes require_verification: true' do
      email = unique_email('sso-jit')
      create_pending_for(email)
      customer = sso_customer(email)
      expect(customer.verified?).to be(true)
      expect(customer.mailbox_verified?).to be(false)

      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      org = result[:organization]
      created_organizations << org

      expect(org.is_default).to be true
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'does not claim on the default path either (lazy creation cannot deliver what JIT deferred)' do
      email = unique_email('sso-lazy')
      create_pending_for(email)
      customer = sso_customer(email)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'does not claim for a held sso_jit record (idp_unverified) on the default path' do
      email = unique_email('sso-held')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false, provisioning_origin: 'sso_jit')
      customer.verification_hold = 'idp_unverified'
      customer.save

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      created_organizations << result[:organization]

      expect(result[:organization].subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'claims once an operator stamps a mailbox-proof provenance (the re-claim trigger)' do
      email = unique_email('sso-operator-verify')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = sso_customer(email)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer, require_verification: true).call
      org = result[:organization]
      created_organizations << org
      expect(pending_exists?(email)).to be(true)

      # `bin/ots customers verify` / colonel admin: verified stays true, only
      # the provenance moves to a mailbox-proof value. Rodauth is already
      # Verified for an SSO account, so this is a Redis-only write.
      outcome = Auth::Operations::SetCustomerVerification.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        rodauth_already_synced: true,
      ).call
      expect(outcome).to eq(:success)
      expect(customer.mailbox_verified?).to be(true)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.planid.to_s).to eq('pro_monthly')
      expect(pending_exists?(email)).to be(false)
    end

    it 'does not claim when the re-verification keeps an IdP-asserted provenance' do
      email = unique_email('sso-still-sso')
      create_pending_for(email)
      customer = sso_customer(email)
      created_organizations << Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)

      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # A workspace that owns a local subscription is never a federation target
  # ---------------------------------------------------------------------------
  describe 'a default workspace that already owns a local subscription' do
    # The deferred re-claim can arrive long after signup: an SSO customer
    # subscribes locally while the cross-region record waits on mailbox proof.
    # Applying the pending record would overwrite the local plan, status and
    # period end, keep the local Stripe subscription id, and destroy the
    # pending record — two sources of truth for one workspace (#4735 review).
    it 'refuses the re-claim, keeps the local plan and leaves the pending record intact' do
      email = unique_email('local-owner')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = create_customer(email: email, verified: true, verified_by: 'sso', provisioning_origin: 'sso_jit')

      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer, require_verification: true).call[:organization]
      created_organizations << org
      expect(pending_exists?(email)).to be(true)

      # Local checkout completes before the operator verifies the address.
      local_sub                   = "sub_local_#{SecureRandom.hex(6)}"
      org.stripe_customer_id      = "cus_local_#{SecureRandom.hex(6)}"
      org.stripe_subscription_id  = local_sub
      org.planid                  = 'team_yearly'
      org.subscription_status     = 'trialing'
      org.subscription_period_end = '1999999999'
      org.save

      customer.verified_by = 'cli_provision'
      customer.save
      expect(customer.mailbox_verified?).to be(true)

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.planid.to_s).to eq('team_yearly')
      expect(org.subscription_status.to_s).to eq('trialing')
      expect(org.subscription_period_end.to_s).to eq('1999999999')
      expect(org.stripe_subscription_id).to eq(local_sub)
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Planless pending records must not be claimed (cross-region catalog miss)
  # ---------------------------------------------------------------------------
  describe 'pending record without a resolved planid' do
    # Regression: PendingFederatedSubscription used to resolve the plan via
    # local catalog lookup, which fails by design for cross-region price IDs,
    # storing planid=nil. Claiming such a record marked the org federated
    # (showing the "subscription synced" notification) while applying no
    # benefit, and destroyed the pending record so nothing could retry.
    it 'skips the claim, does not mark federated, and preserves the pending record' do
      email = unique_email('planless')
      create_pending_for(email, planid: nil)
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      # Workspace exists, but no phantom federation happened: no synced
      # notification, no subscription status, planid stays the free default.
      expect(org.subscription_federated?).to be(false)
      expect(org.show_federation_notification?).to be(false)
      expect(org.subscription_status.to_s).to eq('')
      expect(org.planid.to_s).to eq(Billing::Metadata::FREE_PLAN_ID)

      # The pending record survives for the webhook path to re-sync later.
      expect(pending_exists?(email)).to be(true)

      # The verify-path entry point also refuses it.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency / safety of the verify-path claim entry point
  # ---------------------------------------------------------------------------
  describe 'claim_pending_federation_for is idempotent and safe' do
    it 'is a no-op when there is no pending record' do
      email = unique_email('none-pending')
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)

      # No pending was ever stored -> safe no-op, no error.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(false)
    end

    it 'does not double-apply when the subscription was already claimed' do
      email = unique_email('already-claimed')
      create_pending_for(email)
      # 'email' provenance: the re-claim gate is mailbox_verified?, so a bare
      # verified: true would skip at the gate and pass this example vacuously.
      customer = create_customer(email: email, verified: true, verified_by: 'email')

      # First claim consumes the pending record.
      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)

      # Second invocation (as after_verify_account would do) is a safe no-op.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
    end

    # The first claim saved the org but failed to destroy the record; a
    # cancellation webhook then reached the org directly. An operator's
    # verification retry must not replay the surviving snapshot over the
    # cancellation (#4735 review, F8).
    it 'discards a surviving record the first claim already applied instead of replaying it' do
      email = unique_email('replayed-snapshot')
      pending = create_pending_for(email)
      customer = create_customer(email: email, verified: true, verified_by: 'email')

      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)

      # The record as it would have survived a failed destroy!: same hash, same
      # received_at (the claim ran in the same second it was stored).
      create_pending_for(email, received_at: pending.received_at)

      # Cancellation synced straight to the org by the webhook path.
      org.subscription_status = 'canceled'
      org.planid              = 'free_v1'
      org.save

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_status).to eq('canceled')
      expect(org.planid).to eq('free_v1')
      expect(pending_exists?(email)).to be(false), 'the replayed snapshot must be consumed, not kept for the next retry'
    end

    it 'still applies a record received after the workspace was last synced' do
      email = unique_email('newer-record')
      customer = create_customer(email: email, verified: true, verified_by: 'email')
      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
      created_organizations << org
      org.subscription_synced_at = Time.now.to_i - 3600
      org.save

      create_pending_for(email, planid: 'identity_monthly')

      expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)).to be(true)
      org.refresh!
      expect(org.planid.to_s).to eq('identity_monthly')
      expect(pending_exists?(email)).to be(false)
    end

    it 'is a no-op when the customer is not verified' do
      email = unique_email('claim-unverified')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      # Workspace exists but the customer never verified.
      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      created_organizations << result[:organization]

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end
end
