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
      objid: 'cust_target', extid: 'ur_target',
      email: 'old@example.com', exists?: true, anonymous?: false)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end

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
