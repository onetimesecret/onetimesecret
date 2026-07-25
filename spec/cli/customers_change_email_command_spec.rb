# spec/cli/customers_change_email_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The CLI manifest (lib/onetime/cli.rb) require is applied centrally; require the
# command here so the registry has it regardless of manifest ordering. Both this
# and the manifest line are idempotent.
require 'onetime/cli/customers/change_email_command'
require 'auth/operations/customers/change_email'

# CLI-layer coverage only. The cross-store mutation itself is covered by
# apps/web/auth/spec/operations/customers/change_email_spec.rb — these examples
# assert what the ADAPTER owns: preview-by-default, flag threading, the
# confirmation gate, rendering, and exit codes.
RSpec.describe 'customers change-email', type: :cli do
  let(:result_class) { Auth::Operations::Customers::ChangeEmail::Result }

  let(:customer) do
    double('Customer',
      email: 'old@example.com',
      objid: 'cust_objid',
      extid: 'ur_target',
      obscure_email: 'o***@example.com',
      anonymous?: false,
    )
  end

  let(:op) { instance_double(Auth::Operations::Customers::ChangeEmail) }

  def build_result(status:, **overrides)
    result_class.new(
      **{
        status: status,
        extid: 'ur_target',
        from: 'old@example.com',
        to: 'new@example.com',
        dry_run: status == :planned,
        auth_row_updated: status == :success,
        orgs_reindexed: 0,
        sessions_revoked: false,
        verification_reset: false,
        warnings: [],
      }.merge(overrides),
    )
  end

  before do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(customer)
    allow(Auth::Operations::Customers::ChangeEmail).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(build_result(status: :planned))
  end

  describe 'preview by default' do
    it 'calls the op with dry_run: true and exits 0' do
      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(dry_run: true))
      expect(output[:stdout]).to include('PREVIEW')
      expect(output[:stdout]).to include('--apply')
      expect(last_exit_code).to eq(0)
    end

    it 'never prompts for confirmation on the preview path' do
      expect($stdin).not_to receive(:gets)

      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com')
    end

    it 'passes the CLI_ACTOR sentinel, never a synthesized Customer' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(actor: Onetime::CLI::Customers::Shared::CLI_ACTOR))
    end

    it 'normalizes the new address before handing it to the op' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', '  NEW@Example.COM ')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(new_email: 'new@example.com'))
    end
  end

  describe '--apply' do
    before do
      allow(op).to receive(:call).and_return(build_result(status: :success))
    end

    it 'calls the op with dry_run: false and exits 0 with --yes' do
      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(dry_run: false))
      expect(output[:stdout]).to include('Changed ur_target')
      expect(last_exit_code).to eq(0)
    end

    it 'proceeds when the operator answers y at the prompt' do
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply')

      expect(op).to have_received(:call)
      expect(output[:stdout]).to include('Changed ur_target')
      expect(last_exit_code).to eq(0)
    end

    it 'aborts cleanly at EOF without calling the op' do
      allow($stdin).to receive(:gets).and_return(nil)

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply')

      expect(op).not_to have_received(:call)
      expect(output[:stdout]).to include('Aborted.')
      expect(last_exit_code).to eq(0)
    end

    it 'refuses --json --apply without --yes' do
      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--json')

      expect(op).not_to have_received(:call)
      expect(JSON.parse(output[:stdout])['error']).to include('--yes')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects --apply combined with --dry-run' do
      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--dry-run')

      expect(op).not_to have_received(:call)
      expect(output[:stdout]).to include('contradictory')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'flag threading' do
    it 'defaults to resetting verification, notifying, and revoking sessions' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new).with(
        hash_including(
          require_verification: true,
          notify: true,
          revoke_sessions: true,
          allow_closed_account_reuse: false,
          reason: nil,
          ticket: nil,
        ),
      )
    end

    it 'maps --keep-verified to require_verification: false' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--keep-verified')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(require_verification: false))
    end

    it 'maps --no-notify and --no-revoke-sessions' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--no-notify', '--no-revoke-sessions')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(notify: false, revoke_sessions: false))
    end

    it 'threads --reason and --ticket into the op (D41 audit provenance)' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--reason', 'typo fix', '--ticket', 'Z-42')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(reason: 'typo fix', ticket: 'Z-42'))
    end

    it 'maps --allow-closed-account-reuse' do
      run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--allow-closed-account-reuse')

      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new)
        .with(hash_including(allow_closed_account_reuse: true))
    end
  end

  describe 'non-success statuses' do
    it 'surfaces :partial distinctly and exits non-zero' do
      allow(op).to receive(:call).and_return(
        build_result(status: :partial, auth_row_updated: true,
          warnings: %i[secondary_writes_incomplete]),
      )

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes')

      expect(output[:stdout]).to include('PARTIAL')
      expect(output[:stdout]).not_to include('Changed ur_target')
      expect(output[:stdout]).to include('customers doctor')
      expect(output[:stdout]).to include('secondary_writes_incomplete')
      expect(last_exit_code).to eq(1)
    end

    # The swap LANDED, so this is not :partial — but the account is still marked
    # verified on an address nobody has proven they own. It must not read as
    # success and must not tell the operator to retry the change.
    it 'surfaces :verification_not_reset with the remediation and exits non-zero' do
      allow(op).to receive(:call).and_return(
        build_result(status: :verification_not_reset, auth_row_updated: true,
          warnings: %i[verification_reset_failed verification_still_set]),
      )

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes')

      expect(output[:stdout]).to include('VERIFICATION WAS NOT RESET')
      expect(output[:stdout]).not_to include('Changed ur_target')
      expect(output[:stdout]).to include('customers unverify ur_target')
      expect(output[:stdout]).to include('verification_still_set')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 on :email_taken and names the closed-account escape hatch' do
      allow(op).to receive(:call).and_return(build_result(status: :email_taken))

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes')

      expect(output[:stdout]).to include('already in use')
      expect(output[:stdout]).to include('--allow-closed-account-reuse')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 0 on :no_change' do
      allow(op).to receive(:call).and_return(build_result(status: :no_change))

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes')

      expect(output[:stdout]).to include('already uses')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when the customer cannot be resolved' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

      output = run_cli_command_quietly('customers', 'change-email',
        'missing@example.com', 'new@example.com')

      expect(output[:stdout]).to include('Customer not found')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 for an anonymous customer' do
      allow(customer).to receive(:anonymous?).and_return(true)

      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com')

      expect(output[:stdout]).to include('anonymous')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects a malformed new address before calling the op' do
      output = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'not-an-email')

      expect(op).not_to have_received(:call)
      expect(output[:stdout]).to include('Invalid email address')
      expect(last_exit_code).to eq(1)
    end
  end

  describe '--json' do
    it 'emits the full result payload on the preview path' do
      allow(op).to receive(:call).and_return(
        build_result(status: :planned, orgs_reindexed: 3, warnings: %i[new_address_suppressed]),
      )

      output  = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload['status']).to eq('planned')
      expect(payload['extid']).to eq('ur_target')
      expect(payload['dry_run']).to be(true)
      expect(payload['orgs_reindexed']).to eq(3)
      expect(payload['warnings']).to eq(['new_address_suppressed'])
      expect(last_exit_code).to eq(0)
    end

    it 'obscures the OLD address in the payload' do
      output  = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload['from']).not_to eq('old@example.com')
      expect(payload['from']).to eq(OT::Utils.obscure_email('old@example.com'))
    end

    it 'exits 1 while still emitting the payload on :verification_not_reset' do
      allow(op).to receive(:call).and_return(
        build_result(status: :verification_not_reset, warnings: %i[verification_still_set]),
      )

      output  = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload['status']).to eq('verification_not_reset')
      expect(payload['verification_reset']).to be(false)
      expect(payload['warnings']).to eq(['verification_still_set'])
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 while still emitting the payload on :partial' do
      allow(op).to receive(:call).and_return(build_result(status: :partial))

      output  = run_cli_command_quietly('customers', 'change-email',
        'old@example.com', 'new@example.com', '--apply', '--yes', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload['status']).to eq('partial')
      expect(last_exit_code).to eq(1)
    end
  end
end
