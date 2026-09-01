# apps/api/colonel/spec/logic/colonel/change_user_email_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'auth/operations/customers/change_email'

# Adapter-layer coverage only. The cross-store swap itself is covered by
# apps/web/auth/spec/operations/customers/change_email_spec.rb, and the CLI
# adapter by spec/cli/customers_change_email_command_spec.rb. These examples
# assert what THIS adapter owns: preview-by-default, dry_run parsing, and the
# two statuses that must never come back as a 200.
RSpec.describe ColonelAPI::Logic::Colonel::ChangeUserEmail do
  let(:result_class) { Auth::Operations::Customers::ChangeEmail::Result }
  let(:op) { instance_double(Auth::Operations::Customers::ChangeEmail) }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target', role: 'customer',
      email: 'old@example.com', exists?: true, anonymous?: false)
  end

  # The apply path requires the account's CURRENT address in X-OTS-Confirm
  # (#4326); the preview path requires nothing. `confirm_token` is where the
  # colonel session auth strategy puts the percent-decoded header — never params.
  def strategy_result_for(confirm_token = 'old@example.com', session = {})
    double('StrategyResult', session: session, user: colonel,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  let(:strategy_result) { strategy_result_for }

  # Defaults mirror the op's reporting under this adapter's flags
  # (require_verification: true, revoke_sessions: true): the swap-landed
  # statuses — :success, :verification_not_reset, and the :partial carrying
  # :secondary_writes_incomplete — report the auth-row write and the follow-up
  # revocation; everything else reports false. `verification_reset` is false
  # exactly where the op says the reset did NOT land: the downgraded status and
  # the warning of the same name.
  def build_result(status:, **overrides)
    warnings = overrides.fetch(:warnings, [])
    landed   = %i[success verification_not_reset].include?(status) ||
      (status == :partial && warnings.include?(:secondary_writes_incomplete))

    result_class.new(
      **{
        status: status,
        extid: 'ur_target',
        from: 'old@example.com',
        to: 'new@example.com',
        dry_run: status == :planned,
        auth_row_updated: landed,
        orgs_reindexed: 0,
        sessions_revoked: landed,
        verification_reset: landed && status != :verification_not_reset &&
          !warnings.include?(:verification_not_reset),
        warnings: warnings,
      }.merge(overrides),
    )
  end

  # Builds the logic with the two required params plus whatever the example is
  # exercising, and pins the op's answer. Callers still drive raise_concerns
  # (which resolves @user) before process, exactly as the controller does.
  def logic_for(params = {}, status: :planned, **result_overrides)
    allow(op).to receive(:call).and_return(build_result(status: status, **result_overrides))
    described_class.new(
      strategy_result,
      { 'user_id' => 'ur_target', 'new_email' => 'new@example.com' }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Auth::Operations::Customers::ChangeEmail).to receive(:new).and_return(op)
  end

  # ---- Server-side confirmation (#4326) --------------------------------------
  #
  # The token is the account's CURRENT address, not the new one: it names what
  # the operator is changing away from, and the URL (an extid) never carries it.
  # The preview is EXEMPT — it writes nothing.
  describe 'confirmation' do
    let(:expected_confirm_token) { 'old@example.com' }

    def confirmed_logic_for(confirm_token)
      allow(op).to receive(:call).and_return(build_result(status: :success))
      described_class.new(
        strategy_result_for(confirm_token),
        { 'user_id' => 'ur_target', 'new_email' => 'new@example.com', 'dry_run' => 'false' },
      )
    end

    it_behaves_like 'a confirmed colonel action'

    it 'requires no confirmation for a dry-run preview' do
      allow(op).to receive(:call).and_return(build_result(status: :planned))
      logic = described_class.new(
        strategy_result_for(nil),
        { 'user_id' => 'ur_target', 'new_email' => 'new@example.com' },
      )

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'does not accept the NEW address as confirmation' do
      expect { confirmed_logic_for('new@example.com').raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end
  end

  # ---- Step-up (sudo) window (#4327) -----------------------------------------
  describe 'elevation' do
    let(:expected_confirm_token) { 'old@example.com' }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      allow(op).to receive(:call).and_return(build_result(status: :success))
      described_class.new(
        strategy_result_for(confirm_token, session),
        { 'user_id' => 'ur_target', 'new_email' => 'new@example.com', 'dry_run' => 'false' },
      )
    end

    it_behaves_like 'an elevated colonel action'
  end

  describe 'dry_run defaults to preview' do
    it 'is true when the param is absent, and reaches the op that way' do
      logic = logic_for
      expect(logic.dry_run).to be true

      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(dry_run: true))
    end

    # JSON bodies deliver native booleans; consoles and curl deliver strings.
    %w[true 1 yes on TRUE On].each do |raw|
      it "treats #{raw.inspect} as a preview" do
        expect(logic_for({ 'dry_run' => raw }).dry_run).to be true
      end
    end

    it 'treats a native JSON true as a preview' do
      expect(logic_for({ 'dry_run' => true }).dry_run).to be true
    end

    ['false', '0', 'no', 'off', '', false].each do |raw|
      it "treats #{raw.inspect} as an explicit opt-out" do
        expect(logic_for({ 'dry_run' => raw }).dry_run).to be false
      end
    end

    # Documents current behaviour, which fails OPEN: anything outside the
    # truthy allowlist applies the change rather than previewing it.
    it 'treats an unrecognized value as an opt-out' do
      expect(logic_for({ 'dry_run' => 'maybe' }).dry_run).to be false
    end
  end

  describe 'flag defaults threaded into the op' do
    it 'notifies, revokes sessions, and requires re-verification' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(notify: true, revoke_sessions: true, require_verification: true))
    end

    it 'maps keep_verified to require_verification: false' do
      logic = logic_for({ 'keep_verified' => 'true' })
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(require_verification: false))
    end
  end

  # ---- Last active colonel lockout interlock (#4328 review) ------------------
  #
  # ChangeEmail clears verification with enforce_interlocks:false, so changing the
  # last active colonel's email would unverify them, and has_system_role? refuses
  # every unverified account — locking the install out of /colonel entirely. The
  # apply path refuses that; keep_verified is the escape hatch.
  describe 'last active colonel lockout' do
    let(:colonel_target) do
      instance_double(Onetime::Customer,
        objid: 'cust_last', extid: 'ur_last', email: 'boss@example.com',
        role: 'colonel', verified?: true, exists?: true, anonymous?: false)
    end

    def change_email_logic(params = {})
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(op).to receive(:call).and_return(build_result(status: :success))
      described_class.new(
        double('StrategyResult', session: {}, user: colonel,
          auth_method: 'sessionauth', metadata: { confirm_token: 'boss@example.com' }),
        { 'user_id' => 'ur_last', 'new_email' => 'new@example.com', 'dry_run' => 'false' }.merge(params),
      )
    end

    it 'refuses when the change would clear the last active colonel verification' do
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return([colonel_target])

      expect { change_email_logic.raise_concerns }
        .to raise_error(Onetime::FormError, /last active colonel/i)
      expect(op).not_to have_received(:call)
    end

    it 'allows it when keep_verified=true preserves verification (the escape hatch)' do
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return([colonel_target])

      expect { change_email_logic('keep_verified' => 'true').raise_concerns }.not_to raise_error
    end

    it 'allows it when a second verified colonel exists (roster stays populated)' do
      second = instance_double(Onetime::Customer,
        objid: 'cust_second', role: 'colonel', verified?: true, exists?: true)
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel')
        .and_return([colonel_target, second])

      expect { change_email_logic.raise_concerns }.not_to raise_error
    end

    it 'does not fire on a plain (non-colonel) target' do
      # target is role: customer; the default apply-path examples already exercise
      # this, but pin it: no roster read, no refusal.
      expect { logic_for({ 'dry_run' => 'false' }, status: :success).raise_concerns }
        .not_to raise_error
    end
  end

  describe 'status mapping' do
    it 'returns the success shape on :success with obscured addresses' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :success)
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:status]).to eq('success')
      expect(data[:record][:user_id]).to eq('cust_target')
      expect(data[:details][:changed]).to be true
      expect(data[:details][:message]).to eq('Email changed')
      expect(data[:record][:from]).to eq(OT::Utils.obscure_email('old@example.com'))
      expect(data[:record][:from]).not_to eq('old@example.com')
    end

    it 'returns the preview shape on :planned' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:details][:changed]).to be false
      expect(data[:details][:dry_run]).to be true
      expect(data[:details][:message]).to eq('Preview only — no changes applied')
    end

    # SQL committed, Redis did not finish: the two stores may now disagree, so
    # this MUST NOT read as a 200.
    it 'raises a form error on :partial rather than returning success' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :partial,
        warnings: %i[secondary_writes_incomplete])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /PARTIAL/)
      expect { logic.process }.to raise_error(Onetime::FormError, /customers doctor/)
    end

    # A landed partial: the Customer hash committed, the follow-up phase ran,
    # and the verification reset failed. The swap already stuck, so the generic
    # doctor-then-retry guidance is wrong here — the message must carry the
    # unverify-now remediation instead.
    it 'routes a landed :partial carrying :verification_not_reset to unverify, not retry' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :partial,
        warnings: %i[secondary_writes_incomplete verification_not_reset])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.message).to match(/customers unverify ur_target/)
        expect(err.message).not_to match(/before retrying/)
        expect(err.message).to include('verification_not_reset')
      end
    end

    # The op's partial() has a sub-case that appends no warning, so the
    # parenthetical must disappear rather than render as "()".
    it 'omits the warnings parenthetical on a :partial with no warnings' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :partial, warnings: [])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.message).to include('before retrying')
        expect(err.message).not_to include('()')
      end
    end

    # The swap LANDED but the account is still flagged verified on an address
    # nobody has proven they own. Also must not read as a 200, and must not
    # tell the operator to retry the change.
    it 'raises a form error on :verification_not_reset with the remediation' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :verification_not_reset,
        warnings: %i[verification_still_set])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /customers unverify ur_target/)
      expect { logic.process }.to raise_error(Onetime::FormError, /verification_still_set/)
    end
  end
end
