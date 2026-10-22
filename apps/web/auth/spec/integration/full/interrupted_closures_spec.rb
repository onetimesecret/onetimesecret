# apps/web/auth/spec/integration/full/interrupted_closures_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #4830. A closure that stopped after removing the sign-in and before
# deleting the Customer record leaves that record in Redis, marked as closing
# (Customer#closure_started_at), with no accounts row. These examples build
# that state from a real sign-up and check the two ways out of it:
#
#   - `bin/ots customers finish-closures` (Customers::FinishClosures) purges
#     every such record, and leaves alone a closure that rolled back (open
#     accounts row), one that may still be running (young marker), and every
#     record no closure has touched.
#   - A new sign-up with the address finishes the closure and gets a new
#     record instead of adopting the old one: the password path
#     (before_create_account), and EnsureCustomerForAccount's backstop for
#     an accounts row that already exists. The SSO JIT path is driven
#     through its callback in omniauth_interrupted_closure_spec.rb.
#
# Runs on every full lane (`full-sqlite`, `full-pg-agnostic`).
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Interrupted account closures (#4830)', type: :integration do
  before(:all) do
    boot_onetime_app
    # Lazily required by the CLI, not autoloaded; needs the app booted.
    require 'auth/operations/customers/finish_closures'
  end

  let(:password) { AuthTestConstants::TEST_PASSWORD }
  let(:an_hour_ago) { Familia.now.to_i - 3600 }

  def sign_up(email)
    Auth::Config.create_account(login: email, password: password)
    Onetime::Customer.find_by_email(OT::Utils.normalize_email(email)) ||
      raise("sign-up did not create a Customer for #{email}")
  end

  # The state a closure leaves when it stops between the auth account and
  # the record: no accounts row, the record still in Redis, marked.
  def interrupt_closure(customer, at: an_hour_ago)
    Auth::Operations::RemoveAuthenticationData.call(extid: customer.extid, revoke_sessions: false)
    customer.mark_closure_started!(at: at)
    customer
  end

  def default_workspace(customer)
    customer.organization_instances.to_a.find { |org| org.is_default.to_s == 'true' }
  end

  def finish(dry_run:)
    Auth::Operations::Customers::FinishClosures.new(dry_run: dry_run, actor: 'cli', reason: 'spec').call
  end

  describe 'customers finish-closures' do
    let!(:interrupted) { interrupt_closure(sign_up(unique_test_email('interrupted'))) }
    let!(:interrupted_workspace) { default_workspace(interrupted) }
    let!(:rolled_back) { sign_up(unique_test_email('rolled-back')).tap { |c| c.mark_closure_started!(at: an_hour_ago) } }
    let!(:running) { interrupt_closure(sign_up(unique_test_email('running')), at: Familia.now.to_i - 30) }
    let!(:untouched) { sign_up(unique_test_email('untouched')) }

    it 'lists only the closures that stopped part-way, and writes nothing on a dry run' do
      result = finish(dry_run: true)

      expect(result.candidates.map { |candidate| candidate[:extid] }).to eq([interrupted.extid])
      expect(result.candidates.first[:closure_started_at]).to eq(an_hour_ago)
      expect(result.results).to be_empty
      expect(interrupted.exists?).to be(true)
    end

    it 'purges those records with their workspace and leaves every other record alone' do
      result = finish(dry_run: false)

      expect(result.results).to contain_exactly(include(extid: interrupted.extid, status: :success))
      expect(interrupted.exists?).to be(false)
      expect(Onetime::Customer.email_exists?(interrupted.email)).to be(false)
      expect(Onetime::Organization.load(interrupted_workspace.objid)).to be_nil
      expect([rolled_back, running, untouched].map(&:exists?)).to eq([true, true, true])
      expect(auth_db[:accounts].where(external_id: rolled_back.extid).count).to eq(1)
    end

    it 'finds nothing the second time' do
      finish(dry_run: false)

      expect(finish(dry_run: true).candidates).to be_empty
    end
  end

  describe 'a new sign-up with the address' do
    let(:email) { unique_test_email('resignup') }
    let!(:leftover) { interrupt_closure(sign_up(email)) }

    it 'finishes the closure and gets a new record on the password path' do
      customer = sign_up(email)

      expect(customer.extid).not_to eq(leftover.extid)
      expect(customer.closing?).to be(false)
      expect(leftover.exists?).to be(false)
      expect(auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).get(:external_id))
        .to eq(customer.extid)
    end

    it 'refuses the password sign-up under its own event when the closure cannot be finished' do
      refused = Auth::Operations::Customers::Purge::Result.new(
        status: :refused, extid: leftover.extid, custid: nil, blockers: [{ code: :org_has_members }],
      )
      allow(Auth::Operations::Customers::Purge).to receive(:new)
        .and_return(instance_double(Auth::Operations::Customers::Purge, call: refused))
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      expect { Auth::Config.create_account(login: email, password: password) }
        .to raise_error(Rodauth::InternalRequestError)

      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :interrupted_closure_not_finished,
        hash_including(level: :error, status: :refused, blockers: [{ code: :org_has_members }]),
      )
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:registration_blocked_interrupted_closure, hash_including(external_id: leftover.extid))
      expect(Auth::Logging).not_to have_received(:log_auth_event).with(:registration_blocked_redis_conflict, anything)
      expect(leftover.exists?).to be(true)
      expect(auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).count).to eq(0)
    end

    # The closure may still be running (an administrative purge deletes the
    # accounts row before the record), so the sign-up waits it out.
    it 'refuses the sign-up, purging nothing, while the closure is under 15 minutes old' do
      recent = interrupt_closure(sign_up(unique_test_email('recent')), at: Familia.now.to_i - 60)
      allow(Auth::Operations::Customers::Purge).to receive(:new).and_call_original
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      expect { Auth::Config.create_account(login: recent.email, password: password) }
        .to raise_error(Rodauth::InternalRequestError)

      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:interrupted_closure_not_finished, hash_including(reason: :closure_in_progress))
      expect(recent.exists?).to be(true)
    end

    # The invite preconditions run before anything is written to Redis; the
    # leftover is finished only once they pass.
    it 'leaves the record alone when an invite precondition refuses the sign-up' do
      allow(Auth::Operations::Customers::Purge).to receive(:new).and_call_original

      expect do
        Auth::Config.create_account(login: email, password: password, params: { 'invite_token' => 'no-such-token' })
      end.to raise_error(Rodauth::InternalRequestError)

      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
      expect(leftover.exists?).to be(true)
      expect(leftover.closing?).to be(true)
    end

    # EnsureCustomerForAccount adopts an existing record by email once the
    # accounts row exists. Every sign-up path has finished or refused a
    # leftover closure before inserting the row; this is the backstop for a
    # record marked in between.
    context 'when the accounts row already exists (adopting callers)' do
      let!(:account_id) do
        auth_db[:accounts].insert(
          email: OT::Utils.normalize_email(email),
          status_id: AuthTestConstants::STATUS_VERIFIED,
        )
      end

      def ensure_customer
        Auth::Operations::EnsureCustomerForAccount.new(
          account_id: account_id,
          account: { id: account_id, email: email },
          db: auth_db,
          provisioning_origin: 'sso_jit',
        ).call
      end

      it 'finishes the closure and links a new record' do
        customer = ensure_customer

        expect(customer.extid).not_to eq(leftover.extid)
        expect(customer.closing?).to be(false)
        expect(leftover.exists?).to be(false)
        expect(auth_db[:accounts].where(id: account_id).get(:external_id)).to eq(customer.extid)
      end

      # A marked record with its own open accounts row is a closure that
      # rolled back; the finish never purges a live account.
      it 'never purges a marked record that has an open auth account' do
        rolled_back = sign_up(unique_test_email('rolled-back'))
        rolled_back.mark_closure_started!(at: an_hour_ago)
        allow(Auth::Operations::Customers::Purge).to receive(:new).and_call_original

        expect(Auth::Operations::EnsureCustomerForAccount.finish_leftover_closure(rolled_back.email)&.extid)
          .to eq(rolled_back.extid)
        expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
        expect(rolled_back.exists?).to be(true)
      end

      it 'refuses to adopt the record when the closure cannot be finished' do
        refused = Auth::Operations::Customers::Purge::Result.new(status: :refused, extid: leftover.extid, custid: nil)
        allow(Auth::Operations::Customers::Purge).to receive(:new)
          .and_return(instance_double(Auth::Operations::Customers::Purge, call: refused))

        expect { ensure_customer }.to raise_error(Onetime::Problem, /could not be finished/)
        expect(auth_db[:accounts].where(id: account_id).get(:external_id)).to be_nil
        expect(leftover.exists?).to be(true)
      end
    end
  end
end
