# apps/api/account/spec/logic/account/confirm_email_change_spec.rb
#
# frozen_string_literal: true

# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/account/confirm_email_change_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'
require 'auth/operations/customers/change_email'

# Adapter-layer coverage for the one piece of the email-change swap this class
# still owns after #3731 PR-C2: dropping the CURRENT request's Rack session
# (`clear_current_session` / `swap_landed?`). The cross-store mutation is covered
# by apps/web/auth/spec/operations/customers/change_email_spec.rb and the live
# token path by try/unit/logic/account/email_change_try.rb — but every case there
# drives `:success`, a status that cleared the session both before and after the
# gate existed. These examples drive the OTHER statuses, pinning the gate in both
# directions: widen it and an `:email_taken` redemption signs the caller out of an
# account that never changed hands; narrow it and the `:partial` whose swap LANDED
# skips `sess.clear`, so the middleware writes this session back and re-creates the
# blob RevokeAllForCustomer just deleted.
#
# The operation itself is stubbed — this is the adapter's contract, not the op's.
RSpec.describe AccountAPI::Logic::Account::ConfirmEmailChange do
  let(:result_class) { Auth::Operations::Customers::ChangeEmail::Result }
  let(:op) { instance_double(Auth::Operations::Customers::ChangeEmail) }
  let(:token) { 'tok-confirm-email-change' }
  let(:new_email) { 'new@example.com' }

  let(:owner) do
    instance_double(Onetime::Customer,
      objid: 'cust_owner',
      extid: 'ur_owner',
      email: 'old@example.com',
      pending_email_change: token)
  end

  let(:secret) do
    instance_double(Onetime::Secret,
      identifier: token,
      exists?: true,
      custid: 'cust_owner',
      verification?: true,
      load_owner: owner,
      decrypted_secret_value: new_email)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    # The fail-closed `else` arm logs through Onetime::LoggerMethods#auth_logger.
    allow(Onetime).to receive(:get_logger).and_return(double('Logger').as_null_object)
    allow(Onetime.auth_config).to receive(:sso_only_enabled?).and_return(false)
    allow(Onetime::Secret).to receive(:find_by_identifier).with(token).and_return(secret)
    allow(Auth::Operations::Customers::ChangeEmail).to receive(:new).and_return(op)
  end

  # Seeded rather than empty: an assertion against `{}` would pass whether or not
  # anything cleared it.
  def fresh_session
    { 'sid' => 'sid-under-test', 'authenticated' => true }
  end

  def build_result(status, warnings)
    result_class.new(
      status: status,
      extid: 'ur_owner',
      from: 'old@example.com',
      to: new_email,
      dry_run: false,
      auth_row_updated: %i[success partial verification_not_reset].include?(status),
      orgs_reindexed: 0,
      sessions_revoked: %i[success verification_not_reset].include?(status),
      verification_reset: false,
      warnings: warnings,
    )
  end

  # Keyword-only, deliberately: a positional params hash here would swallow a
  # braceless trailing hash at the call site and silently build a default result.
  #
  # Drives the full controller sequence and hands back the session hash plus
  # whatever `process` raised, so an example can assert BOTH — the clear has to be
  # observable on the arms that then raise.
  def confirm(status:, warnings: [], session: fresh_session)
    allow(op).to receive(:call).and_return(build_result(status, warnings))
    strategy_result = double('StrategyResult',
      session: session, user: nil, auth_method: 'noauth', metadata: {})

    logic = described_class.new(strategy_result, { 'token' => token })
    logic.raise_concerns

    error = nil
    begin
      logic.process
    rescue OT::FormError => ex
      error = ex
    end

    [session, error]
  end

  describe "the swap landed — this request's session must go" do
    it 'clears the session on :success' do
      session, error = confirm(status: :success)

      expect(error).to be_nil
      expect(session).to be_empty
    end

    # Idempotent redemption: the account already holds the address and this
    # surface still sends the caller to /signin.
    it 'clears the session on :no_change' do
      session, error = confirm(status: :no_change)

      expect(error).to be_nil
      expect(session).to be_empty
    end

    # The load-bearing case. `:secondary_writes_incomplete` means the Customer
    # hash committed, so both authoritative stores hold the new address and the op
    # ran RevokeAllForCustomer — yet the status mapping raises. The clear has to
    # happen BEFORE that raise or the middleware resurrects the revoked blob.
    it 'clears the session on the :partial that carries :secondary_writes_incomplete, even though process raises' do
      session, error = confirm(status: :partial, warnings: %i[secondary_writes_incomplete])

      expect(error).to be_a(OT::FormError)
      expect(error.message).to eq('Email change could not be completed')
      expect(session).to be_empty
    end

    # Unreachable on this surface today — the adapter passes
    # `require_verification: false`, so the op never produces this status here.
    # But the op only computes it AFTER the swap landed and RevokeAllForCustomer
    # ran, so if that parameter default ever changes, the clear must fire while
    # the mapping still refuses via the fail-closed `else`. Clear-and-raise,
    # same shape as the landed :partial. Both directions are load-bearing:
    # dropping the status from `swap_landed?` resurrects the revoked blob, and
    # whitelisting it in the status mapping reports a clean success for an
    # account left verified on an unproven address.
    it 'clears the session on :verification_not_reset, even though process raises' do
      session, error = confirm(status: :verification_not_reset)

      expect(error).to be_a(OT::FormError)
      expect(error.message).to eq('Email change could not be completed')
      expect(session).to be_empty
    end
  end

  describe 'nothing changed hands — signing the caller out would be gratuitous' do
    # Claimed by another account between the request and this redemption. The
    # caller still owns the address they signed in with.
    it 'leaves the session intact on :email_taken' do
      session, error = confirm(status: :email_taken)

      expect(error).to be_a(OT::FormError)
      expect(error.message).to eq('This email is no longer available')
      expect(session).to eq({ 'sid' => 'sid-under-test', 'authenticated' => true })
    end

    it 'leaves the session intact on :invalid_email' do
      session, error = confirm(status: :invalid_email)

      expect(error).to be_a(OT::FormError)
      expect(session).not_to be_empty
    end

    it 'leaves the session intact on :not_found' do
      session, error = confirm(status: :not_found)

      expect(error).to be_a(OT::FormError)
      expect(session).not_to be_empty
    end

    # The OTHER :partial sub-case: the Customer hash never took the new address,
    # so the op wrote the old one back to `accounts` and revoked nothing. Status
    # alone is not enough to decide — the warning is what separates the two.
    it 'leaves the session intact on a :partial that rolled the auth row back' do
      session, error = confirm(status: :partial, warnings: %i[auth_row_rolled_back])

      expect(error).to be_a(OT::FormError)
      expect(session).not_to be_empty
    end
  end

  # `clear_current_session` now runs before the status mapping, so its nil guard
  # is reached on the raising arms too.
  it 'tolerates a request with no Rack session on an arm that raises' do
    expect { confirm(status: :partial, warnings: %i[secondary_writes_incomplete], session: nil) }
      .not_to raise_error
  end
end
