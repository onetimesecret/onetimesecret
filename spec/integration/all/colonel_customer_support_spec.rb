# spec/integration/all/colonel_customer_support_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'json'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Integration tests for the customer-support colonel features against real
# Redis (port 2163; type: :integration flushes after each example):
#
#   1. Customer search — ListUsers `search` param (bounded email-index HSCAN).
#   2. Billing read-out — GetUserDetails `details.billing` graceful degradation
#      (billing disabled / no Stripe identity / Stripe erroring / Stripe live).
#   3. Account suspend — SuspendUser/UnsuspendUser (audit + session revocation
#      + colonel privilege guard), login rejection (AuthenticateSession) and
#      session-auth rejection (BaseSessionAuthStrategy) for suspended accounts.
RSpec.describe 'Colonel customer support features', type: :integration do
  # Build the StrategyResult double Logic::Base expects (mirrors
  # entitlement_preview_spec.rb). The colonel is a REAL verified customer so
  # verify_one_of_roles!(colonel: true) exercises the actual policy.
  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header (#4326) — never params. The gated verbs
  # exercised below refuse without it.
  def strategy_result_for(user, session: {}, confirm_token: nil)
    double(
      'StrategyResult',
      session: session,
      user: user,
      metadata: { ip: '127.0.0.1', confirm_token: confirm_token },
      auth_method: 'sessionauth',
    )
  end

  def create_customer(email:, role: 'customer', verified: 'true')
    cust          = Onetime::Customer.create!(email: email)
    cust.role     = role
    cust.verified = verified
    cust.save
    cust
  end

  let(:colonel) do
    create_customer(email: "colonel-#{SecureRandom.hex(4)}@example.com", role: 'colonel')
  end

  # ---------------------------------------------------------------------------
  # 1. Customer search (ListUsers `search` param)
  # ---------------------------------------------------------------------------
  describe 'ListUsers email search' do
    it 'returns only customers whose email contains the term (case-insensitive)' do
      alice = create_customer(email: 'alice-search@example.com')
      create_customer(email: 'bob-other@example.com')

      logic = ColonelAPI::Logic::Colonel::ListUsers.new(
        strategy_result_for(colonel), { 'search' => 'ALICE-SEARCH' },
      )
      logic.raise_concerns
      data = logic.process

      extids = data[:details][:users].map { |u| u[:extid] }
      expect(extids).to eq([alice.extid])
      expect(data[:details][:pagination][:total_count]).to eq(1)
      expect(data[:details][:pagination][:search]).to eq('ALICE-SEARCH')
    end

    it 'returns an empty page (not an error) when nothing matches' do
      create_customer(email: 'someone@example.com')

      logic = ColonelAPI::Logic::Colonel::ListUsers.new(
        strategy_result_for(colonel), { 'search' => 'no-such-account' },
      )
      logic.raise_concerns
      data = logic.process

      expect(data[:details][:users]).to eq([])
      expect(data[:details][:pagination][:total_count]).to eq(0)
    end

    it 'includes the suspended flag on list rows' do
      target = create_customer(email: 'suspended-row@example.com')
      Auth::Operations::Customers::SetSuspension.new(
        customer: target, suspended: true, actor: colonel.extid,
      ).call

      logic = ColonelAPI::Logic::Colonel::ListUsers.new(
        strategy_result_for(colonel), { 'search' => 'suspended-row' },
      )
      logic.raise_concerns
      data = logic.process

      expect(data[:details][:users].first[:suspended]).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Billing on the customer page (GetUserDetails details.billing)
  # ---------------------------------------------------------------------------
  describe 'GetUserDetails billing read-out' do
    def user_details(target)
      logic = ColonelAPI::Logic::Colonel::GetUserDetails.new(
        strategy_result_for(colonel), { 'user_id' => target.extid },
      )
      logic.raise_concerns
      logic.process
    end

    let(:target) do
      cust        = create_customer(email: "billing-#{SecureRandom.hex(4)}@example.com")
      cust.planid = 'identity_plus_v1'
      cust.save
      cust
    end

    it 'degrades to plan-from-model when billing is not configured (test default)' do
      data    = user_details(target)
      billing = data[:details][:billing]

      expect(billing[:enabled]).to be(false)
      expect(billing[:plan_id]).to eq('identity_plus_v1')
      expect(billing[:stripe][:available]).to be(false)
      expect(billing[:stripe][:reason]).to eq('Billing is not configured')
      expect(billing[:stripe][:latest_invoice]).to be_nil
    end

    it 'degrades to "no Stripe customer linked" when enabled but no Stripe identity' do
      allow(Onetime.billing_config).to receive(:enabled?).and_return(true)
      stub_const('Stripe', Module.new)

      billing = user_details(target)[:details][:billing]

      expect(billing[:enabled]).to be(true)
      expect(billing[:plan_id]).to eq('identity_plus_v1')
      expect(billing[:stripe][:available]).to be(false)
      expect(billing[:stripe][:reason]).to eq('No Stripe customer linked')
    end

    context 'with a billing organization carrying Stripe identifiers' do
      let(:billing_org) do
        double(
          'Organization',
          extid: 'og_billing',
          display_name: 'Billing Org',
          planid: 'identity_plus_v1',
          subscription_status: 'active',
          subscription_period_end: '1700003600',
          stripe_customer_id: 'cus_test123',
          stripe_subscription_id: 'sub_test123',
          is_default: true,
        )
      end

      before do
        allow(Onetime.billing_config).to receive(:enabled?).and_return(true)
        allow(Onetime.billing_config).to receive(:stripe_key).and_return('sk_test_abc')
      end

      def stub_billing_org(logic)
        allow(logic).to receive(:billing_organization).and_return(billing_org)
        logic
      end

      def details_with_org(target)
        logic = ColonelAPI::Logic::Colonel::GetUserDetails.new(
          strategy_result_for(colonel), { 'user_id' => target.extid },
        )
        logic.raise_concerns
        stub_billing_org(logic)
        logic.process
      end

      it 'degrades (never 500s) when Stripe raises, keeping local plan data' do
        failing = Class.new do
          def self.retrieve(*) = raise(StandardError, 'stripe timeout')
          def self.list(*) = raise(StandardError, 'stripe timeout')
        end
        stub_const('Stripe', Module.new)
        stub_const('Stripe::Subscription', failing)
        stub_const('Stripe::Invoice', failing)

        billing = details_with_org(target)[:details][:billing]

        expect(billing[:stripe][:available]).to be(false)
        expect(billing[:stripe][:reason]).to include('stripe timeout')
        # Local data survives the Stripe outage.
        expect(billing[:plan_id]).to eq('identity_plus_v1')
        expect(billing[:organization][:subscription_status]).to eq('active')
        # The dashboard deep link still renders from the stored customer id.
        expect(billing[:stripe][:dashboard_url]).to eq(
          'https://dashboard.stripe.com/test/customers/cus_test123',
        )
      end

      it 'returns subscription + latest invoice + dashboard link when Stripe responds' do
        item         = double('Item', current_period_end: 1_700_003_600)
        subscription = double(
          'Subscription',
          id: 'sub_test123', status: 'active', items: double(data: [item]),
        )
        invoice = double(
          'Invoice',
          id: 'in_test1', number: 'INV-0001', status: 'paid', currency: 'usd',
          total: 3500, created: 1_700_000_000,
          hosted_invoice_url: 'https://invoice.stripe.com/i/in_test1',
        )
        sub_api = double('SubAPI')
        allow(sub_api).to receive(:retrieve).with('sub_test123').and_return(subscription)
        inv_api = double('InvAPI')
        allow(inv_api).to receive(:list)
          .with(customer: 'cus_test123', limit: 1)
          .and_return(double(data: [invoice]))

        stub_const('Stripe', Module.new)
        stub_const('Stripe::Subscription', sub_api)
        stub_const('Stripe::Invoice', inv_api)

        billing = details_with_org(target)[:details][:billing]

        expect(billing[:stripe][:available]).to be(true)
        expect(billing[:stripe][:subscription]).to eq(
          id: 'sub_test123', status: 'active', current_period_end: 1_700_003_600,
        )
        expect(billing[:stripe][:latest_invoice]).to include(
          number: 'INV-0001', status: 'paid', currency: 'usd', total: 3500,
        )
        expect(billing[:stripe][:dashboard_url]).to eq(
          'https://dashboard.stripe.com/test/customers/cus_test123',
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2b. Activity read-out (GetUserDetails details.secrets / details.receipts)
  #
  # These sections used to walk the entire `secret:*:object` and
  # `receipt:*:object` keyspaces, loading every object one at a time to filter
  # by owner — the 10k guard counted MATCHES, so it never tripped for a normal
  # user and the page timed out. They now read the per-owner indexes
  # (customer:<objid>:secrets / :receipts). What is asserted here is the
  # CONTRACT: the right items, count == items.size, an honest `truncated` flag,
  # and independent degradation.
  # ---------------------------------------------------------------------------
  describe 'GetUserDetails activity read-out' do
    # These examples persist REAL Secrets via spawn_pair: identifier
    # generation needs VERIFIABLE_ID_HMAC_SECRET and ciphertext= needs the
    # encryption keys, both provisioned by configure_familia during FULL
    # boot. An earlier spec's partial or failed boot can leave the process
    # without either (PR #3817 seed-60018 failure class), so guard-boot
    # like the sibling integration specs, and seed the env var for the
    # case where a partial boot already marked the state ready.
    before(:all) do
      ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= SecureRandom.hex(32)
      begin
        OT.boot! :test unless OT.ready?
      rescue Redis::CannotConnectError, Redis::ConnectionError => e
        puts "SKIP: Requires Redis connection (#{e.class})"
        exit 0
      end
    end

    def user_details(target)
      logic = ColonelAPI::Logic::Colonel::GetUserDetails.new(
        strategy_result_for(colonel), { 'user_id' => target.extid },
      )
      logic.raise_concerns
      logic.process
    end

    let(:owner) { create_customer(email: "activity-#{SecureRandom.hex(4)}@example.com") }

    it 'lists only the owner\'s secrets, newest first, with count == items.size' do
      other = create_customer(email: "other-#{SecureRandom.hex(4)}@example.com")
      _r1, first  = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'mine one')
      _r2, second = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'mine two')
      Onetime::Receipt.spawn_pair(other.objid, 3600, 'not mine')

      secrets = user_details(owner)[:details][:secrets]

      expect(secrets[:items].map { |s| s[:secret_id] }).to eq([second.objid, first.objid])
      expect(secrets[:count]).to eq(secrets[:items].size)
      expect(secrets[:truncated]).to be(false)
    end

    it 'drops a destroyed secret from the list (index and counter move together)' do
      _r1, keep    = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'keep')
      _r2, destroy = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'destroy')
      destroy.destroy!

      secrets = user_details(owner)[:details][:secrets]

      expect(secrets[:items].map { |s| s[:secret_id] }).to eq([keep.objid])
      expect(secrets[:count]).to eq(1)
    end

    it 'reports an empty, non-truncated read-out for a customer with no activity' do
      details = user_details(owner)[:details]

      expect(details[:secrets]).to eq(count: 0, items: [], truncated: false)
      expect(details[:receipts]).to eq(count: 0, items: [], truncated: false)
    end

    it 'lists receipts off the per-customer index' do
      receipt, _secret = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'with receipt')
      owner.add_receipt(receipt)

      receipts = user_details(owner)[:details][:receipts]

      expect(receipts[:items].map { |r| r[:receipt_id] }).to eq([receipt.objid])
      expect(receipts[:count]).to eq(1)
      expect(receipts[:truncated]).to be(false)
    end

    it 'flags truncation instead of implying the short list is complete' do
      # Counter says there are more secrets than the index can show (the
      # pre-index / straddling-rollout case).
      Onetime::Receipt.spawn_pair(owner.objid, 3600, 'only indexed one')
      owner.secrets_active.reset(5)

      secrets = user_details(owner)[:details][:secrets]

      expect(secrets[:items].size).to eq(1)
      expect(secrets[:count]).to eq(1)
      expect(secrets[:truncated]).to be(true)
    end

    it 'scan fallback survives legacy String created values, newest first' do
      # The bounded-scan fallback runs only when the per-owner index is empty
      # while the secrets_active counter is positive (the pre-index account
      # shape). Legacy pre-JSON hash fields hydrate as raw Strings — Familia's
      # deserialize_value returns the value as-is when Oj's strict parse fails
      # — and String#-@ is the frozen-string operator, so the old
      # `-(row[:created] || 0)` sort raised ArgumentError on a mixed
      # Float/String batch, which degrade_on_error swallowed into an empty
      # secrets section.
      _r1, legacy = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'legacy value')
      _r2, modern = Onetime::Receipt.spawn_pair(owner.objid, 3600, 'modern value')

      # Simulate pre-JSON-serialization data: write the raw hash field
      # directly. A Time#to_s-shaped value fails Oj strict parse and therefore
      # hydrates as a String (a bare numeric string would parse to a number).
      Onetime::Secret.dbclient.hset(legacy.dbkey, 'created', '2024-01-15 10:30:00 UTC')

      # Empty the index while the counter stays positive: exactly the state
      # that routes collect_secrets into scan_secrets_bounded.
      owner.secrets.delete!
      expect(owner.secrets.element_count).to eq(0)
      expect(owner.secrets_active.to_i).to be_positive

      secrets = user_details(owner)[:details][:secrets]

      # NOT the degraded `{items: [], truncated: true}` shape...
      expect(secrets[:items]).not_to be_empty
      expect(secrets[:truncated]).to be(false)
      # ...and newest first: the unparseable legacy timestamp coerces to a
      # tiny float, so it sorts as oldest.
      expect(secrets[:items].map { |s| s[:secret_id] }).to eq([modern.objid, legacy.objid])
      expect(secrets[:count]).to eq(2)
    end

    it 'still renders identity, plan and billing when the secrets read blows up' do
      logic = ColonelAPI::Logic::Colonel::GetUserDetails.new(
        strategy_result_for(colonel), { 'user_id' => owner.extid },
      )
      logic.raise_concerns
      allow(logic).to receive(:collect_secrets).and_raise(StandardError, 'datastore down')

      data = logic.process

      # The failing section degrades to empty-but-honest...
      expect(data[:details][:secrets]).to eq(count: 0, items: [], truncated: true)
      # ...and the rest of the record renders.
      expect(data[:record][:extid]).to eq(owner.extid)
      expect(data[:record][:email]).to eq(owner.email)
      expect(data[:details][:receipts][:truncated]).to be(false)
      expect(data[:details][:billing]).to include(:enabled, :plan_id)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Account suspend
  # ---------------------------------------------------------------------------
  describe 'SuspendUser / UnsuspendUser' do
    let(:target) { create_customer(email: "target-#{SecureRandom.hex(4)}@example.com") }

    # SUSPEND is confirmation-gated (#4326) on the account email; UNSUSPEND is
    # the restorative arm and ignores the token.
    def run_logic(klass, params, confirm: target.email)
      logic = klass.new(strategy_result_for(colonel, confirm_token: confirm), params)
      logic.raise_concerns
      logic.process
    end

    it 'suspends, revokes the customer session, and writes one audit event' do
      db  = Familia.dbclient
      sid = SecureRandom.hex(32)
      db.set("session:#{sid}", JSON.generate(
        'authenticated' => true, 'external_id' => target.extid, 'email' => target.email,
      ))
      other_sid = SecureRandom.hex(32)
      db.set("session:#{other_sid}", JSON.generate(
        'authenticated' => true, 'external_id' => 'ur_someone_else',
      ))
      audit_before = Onetime::ColonelAuditEvent.count

      data = run_logic(
        ColonelAPI::Logic::Colonel::SuspendUser,
        { 'user_id' => target.extid, 'reason' => 'tos violation' },
      )

      expect(data[:record][:suspended]).to be(true)
      expect(data[:details][:changed]).to be(true)
      expect(data[:details][:sessions_revoked]).to eq(1)

      reloaded = Onetime::Customer.load(target.objid)
      expect(reloaded.suspended?).to be(true)
      expect(reloaded.suspended_reason).to eq('tos violation')
      expect(reloaded.suspended_by).to eq(colonel.extid)

      # The customer's session is gone; the unrelated one survives.
      expect(db.exists("session:#{sid}")).to eq(0)
      expect(db.exists("session:#{other_sid}")).to eq(1)

      # Exactly one audit event, from the op layer.
      expect(Onetime::ColonelAuditEvent.count).to eq(audit_before + 1)
      event = Onetime::ColonelAuditEvent.recent(1).first
      expect(event['verb']).to eq('customer.suspend')
      expect(event['target']).to eq(target.extid)
    end

    it 'unsuspends reversibly (data intact) and audits customer.unsuspend' do
      run_logic(ColonelAPI::Logic::Colonel::SuspendUser, { 'user_id' => target.extid })
      audit_before = Onetime::ColonelAuditEvent.count

      data = run_logic(ColonelAPI::Logic::Colonel::UnsuspendUser, { 'user_id' => target.extid })

      expect(data[:record][:suspended]).to be(false)
      reloaded = Onetime::Customer.load(target.objid)
      expect(reloaded.suspended?).to be(false)
      expect(reloaded.suspended_reason.to_s).to eq('')
      # Nothing destroyed: the account still exists with its email intact.
      expect(reloaded.email).to eq(target.email)

      expect(Onetime::ColonelAuditEvent.count).to eq(audit_before + 1)
      expect(Onetime::ColonelAuditEvent.recent(1).first['verb']).to eq('customer.unsuspend')
    end

    it 'refuses to suspend a colonel-role account (privilege guard)' do
      other_colonel = create_customer(
        email: "colonel2-#{SecureRandom.hex(4)}@example.com", role: 'colonel',
      )
      audit_before = Onetime::ColonelAuditEvent.count

      # The privilege guard is an INTERLOCK, so it runs AFTER the confirmation
      # gate (§0.2): a caller who has not named the target correctly must not
      # learn from a 422 that the account holds the colonel role.
      unconfirmed = ColonelAPI::Logic::Colonel::SuspendUser.new(
        strategy_result_for(colonel), { 'user_id' => other_colonel.extid },
      )
      expect { unconfirmed.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)

      logic = ColonelAPI::Logic::Colonel::SuspendUser.new(
        strategy_result_for(colonel, confirm_token: other_colonel.email),
        { 'user_id' => other_colonel.extid },
      )
      expect { logic.raise_concerns }.to raise_error(OT::FormError, /cannot be suspended/i)

      expect(Onetime::Customer.load(other_colonel.objid).suspended?).to be(false)
      expect(Onetime::ColonelAuditEvent.count).to eq(audit_before)
    end

    it 'rejects non-colonel actors (defense-in-depth below the router role gate)' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::SuspendUser.new(
        strategy_result_for(staff), { 'user_id' => target.extid },
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'is idempotent: re-suspending audits nothing and reports changed=false' do
      run_logic(ColonelAPI::Logic::Colonel::SuspendUser, { 'user_id' => target.extid })
      audit_before = Onetime::ColonelAuditEvent.count

      data = run_logic(ColonelAPI::Logic::Colonel::SuspendUser, { 'user_id' => target.extid })

      expect(data[:details][:changed]).to be(false)
      expect(Onetime::ColonelAuditEvent.count).to eq(audit_before)
    end
  end

  describe 'suspension enforcement at the auth layer' do
    let(:password) { "correct-horse-#{SecureRandom.hex(4)}" }
    let(:target) do
      cust = create_customer(email: "auth-#{SecureRandom.hex(4)}@example.com")
      cust.update_passphrase!(password)
      cust
    end

    def suspend!(cust)
      Auth::Operations::Customers::SetSuspension.new(
        customer: cust, suspended: true, actor: colonel.extid,
      ).call
    end

    describe 'login (AuthenticateSession)' do
      def login_logic(email, pass)
        Core::Logic::Authentication::AuthenticateSession.new(
          strategy_result_for(nil, session: {}),
          { 'login' => email, 'password' => pass },
        )
      end

      it 'rejects a suspended customer even with valid credentials' do
        suspend!(target)

        logic = login_logic(target.email, password)
        logic.raise_concerns
        expect { logic.process }.to raise_error(OT::FormError, /suspended/i)
      end

      it 'accepts the same credentials once unsuspended (reversible)' do
        suspend!(target)
        Auth::Operations::Customers::SetSuspension.new(
          customer: Onetime::Customer.load(target.objid), suspended: false, actor: colonel.extid,
        ).call

        logic = login_logic(target.email, password)
        logic.raise_concerns
        expect { logic.process }.not_to raise_error
        expect(logic.greenlighted).to be(true)
      end
    end

    describe 'session authentication (BaseSessionAuthStrategy)' do
      let(:strategy) { Onetime::Application::AuthStrategies::SessionAuthStrategy.new }

      def env_for(cust)
        {
          'rack.session' => {
            'authenticated' => true,
            'external_id' => cust.extid,
            'email' => cust.email,
          },
        }
      end

      it 'rejects every request from a suspended customer' do
        suspend!(target)

        result = strategy.authenticate(env_for(target), nil)

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.failure_reason).to include('ACCOUNT_SUSPENDED')
      end

      it 'authenticates the same session again once unsuspended' do
        suspend!(target)
        Auth::Operations::Customers::SetSuspension.new(
          customer: Onetime::Customer.load(target.objid), suspended: false, actor: colonel.extid,
        ).call

        result = strategy.authenticate(env_for(target), nil)

        expect(result).not_to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.user.objid).to eq(target.objid)
      end
    end
  end
end
