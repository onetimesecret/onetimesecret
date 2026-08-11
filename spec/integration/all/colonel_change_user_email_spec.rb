# spec/integration/all/colonel_change_user_email_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Adapter-contract tests for ColonelAPI::Logic::Colonel::ChangeUserEmail
# against real Redis (port 2121; type: :integration flushes after each
# example). The class is a thin adapter over
# Auth::Operations::Customers::ChangeEmail — the op owns the swap and the
# ColonelAuditEvent — so the op is stubbed here and the spec pins the adapter's
# own obligations (PR #3915 follow-up: this class previously had no spec):
#
#   1. Parameter contract — dry_run defaults TRUE, safe defaults for
#      notify/revoke_sessions, keep_verified inverts require_verification,
#      actor is the acting colonel's extid, identifier sanitization keeps
#      email-shaped values resolvable.
#   2. Guards — colonel role, required params, unknown user, anonymous user.
#   3. Result-status mapping — which statuses 4xx and which return 200, and
#      that the operator-facing log line survives a nil result.extid.
#   4. Response shape — emails obscured on both sides, documented keys.
RSpec.describe 'Colonel ChangeUserEmail adapter contract', type: :integration do
  # Build the StrategyResult double Logic::Base expects (mirrors
  # colonel_customer_support_spec.rb). The colonel is a REAL verified customer
  # so verify_one_of_roles!(colonel: true) exercises the actual policy.
  def strategy_result_for(user, session: {})
    double(
      'StrategyResult',
      session: session,
      user: user,
      metadata: { ip: '127.0.0.1' },
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

  def result_with(status:, extid: 'exdefault', from: 'old@example.com',
                  to: 'new@example.com', dry_run: false, warnings: [])
    Auth::Operations::Customers::ChangeEmail::Result.new(
      status: status,
      extid: extid,
      from: from,
      to: to,
      dry_run: dry_run,
      auth_row_updated: !dry_run,
      orgs_reindexed: 0,
      sessions_revoked: 0,
      verification_reset: !dry_run,
      warnings: warnings,
    )
  end

  let(:colonel) do
    create_customer(email: "colonel-#{SecureRandom.hex(4)}@example.com", role: 'colonel')
  end
  let(:target) do
    create_customer(email: "target-#{SecureRandom.hex(4)}@example.com")
  end

  let(:op_result) { result_with(status: :planned, dry_run: true) }
  let(:captured_op_args) { {} }

  before do
    allow(Auth::Operations::Customers::ChangeEmail).to receive(:new) do |**kwargs|
      captured_op_args.replace(kwargs)
      instance_double(Auth::Operations::Customers::ChangeEmail, call: op_result)
    end
  end

  def run_logic(params, actor: colonel)
    logic = ColonelAPI::Logic::Colonel::ChangeUserEmail.new(
      strategy_result_for(actor), params,
    )
    logic.raise_concerns
    logic.process
  end

  # ---------------------------------------------------------------------------
  # 1. Parameter contract
  # ---------------------------------------------------------------------------
  describe 'parameter contract' do
    it 'defaults to a dry run with safe notify/revoke/verification settings' do
      data = run_logic({ 'user_id' => target.extid, 'new_email' => 'fresh@example.com' })

      expect(captured_op_args).to include(
        dry_run: true,
        notify: true,
        revoke_sessions: true,
        require_verification: true,
        reason: nil,
        ticket: nil,
      )
      expect(captured_op_args[:customer].objid).to eq(target.objid)
      expect(captured_op_args[:actor]).to eq(colonel.extid)
      expect(data[:details][:dry_run]).to be(true)
      expect(data[:details][:changed]).to be(false)
      expect(data[:details][:message]).to eq('Preview only — no changes applied')
    end

    it 'passes through an explicit apply with per-case opt-outs' do
      op_result = result_with(status: :success)
      allow(Auth::Operations::Customers::ChangeEmail).to receive(:new) do |**kwargs|
        captured_op_args.replace(kwargs)
        instance_double(Auth::Operations::Customers::ChangeEmail, call: op_result)
      end

      data = run_logic({
        'user_id'         => target.extid,
        'new_email'       => 'fresh@example.com',
        'dry_run'         => 'false',
        'keep_verified'   => 'true',
        'notify'          => 'false',
        'revoke_sessions' => 'false',
        'reason'          => 'compromised account',
        'ticket'          => 'SUP-123',
      })

      expect(captured_op_args).to include(
        dry_run: false,
        notify: false,
        revoke_sessions: false,
        require_verification: false, # keep_verified inverts
        reason: 'compromised account',
        ticket: 'SUP-123',
      )
      expect(data[:details][:changed]).to be(true)
      expect(data[:details][:message]).to eq('Email changed')
      expect(data[:record][:status]).to eq('success')
    end

    it 'sanitizes both identifiers while keeping email-shaped values resolvable' do
      # Angle brackets and whitespace are stripped; @ . + survive, so a pasted
      # "<email>" still resolves and the new address is not mangled.
      run_logic({
        'user_id'   => "<#{target.email}>",
        'new_email' => "  Fresh+Addr@Example.com\n",
      })

      expect(captured_op_args[:customer].objid).to eq(target.objid)
      expect(captured_op_args[:new_email]).to eq('Fresh+Addr@Example.com')
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Guards
  # ---------------------------------------------------------------------------
  describe 'guards' do
    it 'rejects non-colonel callers before touching params' do
      plain = create_customer(email: "plain-#{SecureRandom.hex(4)}@example.com")

      expect do
        run_logic({ 'user_id' => target.extid, 'new_email' => 'x@example.com' }, actor: plain)
      end.to raise_error(Onetime::Forbidden)
      expect(Auth::Operations::Customers::ChangeEmail).not_to have_received(:new)
    end

    it 'requires user_id' do
      expect do
        run_logic({ 'new_email' => 'x@example.com' })
      end.to raise_error(OT::FormError) { |e| expect(e.field).to eq(:user_id) }
    end

    it 'requires new_email' do
      expect do
        run_logic({ 'user_id' => target.extid })
      end.to raise_error(OT::FormError) { |e| expect(e.field).to eq(:new_email) }
    end

    it '404s an unknown identifier' do
      expect do
        run_logic({ 'user_id' => 'no-such-user@example.com', 'new_email' => 'x@example.com' })
      end.to raise_error(Onetime::RecordNotFound)
    end

    it 'refuses to modify an anonymous user' do
      # Customer#save refuses anonymous records outright, so flip the stored
      # role directly: the resolver then loads a genuinely anonymous-role
      # customer, which is the state the guard exists for.
      anon = create_customer(email: "anon-#{SecureRandom.hex(4)}@example.com")
      Onetime::Customer.dbclient.hset(anon.dbkey, 'role', 'anonymous')

      expect do
        run_logic({ 'user_id' => anon.email, 'new_email' => 'x@example.com' })
      end.to raise_error(OT::FormError) { |e| expect(e.field).to eq(:user_id) }
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Result-status mapping
  # ---------------------------------------------------------------------------
  describe 'result-status mapping' do
    def run_with_status(status, **result_overrides)
      result = result_with(status: status, **result_overrides)
      allow(Auth::Operations::Customers::ChangeEmail).to receive(:new)
        .and_return(instance_double(Auth::Operations::Customers::ChangeEmail, call: result))
      run_logic({ 'user_id' => target.extid, 'new_email' => 'fresh@example.com' })
    end

    it 'maps :invalid_email to a form error on new_email' do
      expect { run_with_status(:invalid_email) }
        .to raise_error(OT::FormError) { |e| expect(e.field).to eq(:new_email) }
    end

    it 'maps :email_taken to a form error on new_email' do
      expect { run_with_status(:email_taken) }
        .to raise_error(OT::FormError, /already in use/)
    end

    it 'maps :not_found to 404 and keeps the subject in the log via user.extid' do
      log_lines = []
      allow(OT).to receive(:info) { |msg| log_lines << msg }

      expect { run_with_status(:not_found, extid: nil, from: nil, to: nil) }
        .to raise_error(Onetime::RecordNotFound, /no usable email/)

      line = log_lines.find { |msg| msg.include?('[ChangeUserEmail]') }
      expect(line).to include(target.extid)
      expect(line).to include('status=not_found')
    end

    it 'refuses a silent 200 on :partial' do
      expect { run_with_status(:partial) }
        .to raise_error(OT::FormError, /PARTIAL/)
    end

    it 'refuses a silent 200 on :verification_not_reset and names the remediation' do
      expect { run_with_status(:verification_not_reset, warnings: [:verification_reset_failed]) }
        .to raise_error(OT::FormError, /unverify/)
    end

    it 'treats :no_change as an idempotent success' do
      data = run_with_status(:no_change)
      expect(data[:details][:changed]).to be(false)
      expect(data[:details][:message]).to eq('User already uses that email address')
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Response shape
  # ---------------------------------------------------------------------------
  describe 'response shape' do
    it 'obscures both addresses and surfaces warnings as strings' do
      result = result_with(
        status: :success,
        extid: target.extid,
        from: 'old@example.com',
        to: 'new@example.com',
        warnings: [:contact_email_skipped],
      )
      allow(Auth::Operations::Customers::ChangeEmail).to receive(:new)
        .and_return(instance_double(Auth::Operations::Customers::ChangeEmail, call: result))

      data = run_logic({ 'user_id' => target.extid, 'new_email' => 'new@example.com' })

      expect(data[:record]).to include(
        user_id: target.objid,
        extid: target.extid,
        from: OT::Utils.obscure_email('old@example.com'),
        to: OT::Utils.obscure_email('new@example.com'),
        email: OT::Utils.obscure_email('new@example.com'),
      )
      expect(data[:record][:from]).not_to include('old@example.com')
      expect(data[:details][:warnings]).to eq(['contact_email_skipped'])
    end
  end
end
