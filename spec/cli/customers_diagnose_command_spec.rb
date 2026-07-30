# spec/cli/customers_diagnose_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

require 'onetime/cli/customers/diagnose_command'
require 'auth/operations/customers/diagnose'

# CLI-layer coverage only. The diagnosis itself is covered by
# apps/web/auth/spec/operations/customers/diagnose_spec.rb — these examples
# assert what the ADAPTER owns: identifier threading (including the numeric
# Rodauth account id that resolves to no Customer), obscure-by-default for
# emails in JSON output, and the exit code scripted region sweeps branch on.
RSpec.describe 'customers diagnose', type: :cli do
  let(:op) { instance_double(Auth::Operations::Customers::Diagnose) }

  # The op interpolates the auth-side address straight into this message
  # (diagnose.rb, :email_drift), so finding TEXT carries PII no field-name
  # list can reach. Other messages carry one transitively (a PG error excerpt
  # quotes the failing statement, which contains the email literal).
  def drift_message
    'Customer email and auth account email differ ' \
      '(auth side: user@example.com) — reconcile before the user can sign in.'
  end

  # An orphaned auth account: the accounts row exists, no Customer does.
  def orphan_result
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: nil,
      sections: {
        customer: { found: false },
        auth_account: {
          available: true,
          found: true,
          account_id: 42,
          email: 'user@example.com',
          status: 'verified',
        },
        audit_log: {
          available: true,
          entries: [
            {
              at: 1_700_000_000.0,
              message: 'login_failure',
              # String-keyed, as a decoded json column always is.
              metadata: { 'email' => 'user@example.com' },
            },
          ],
        },
        # The limiter keys on the plain normalized email, so the address is
        # embedded in a `key` field. RateLimit::Inspect returns an entry for
        # every exact key whether or not it exists, so the locked-key row is
        # printed on EVERY run — including a perfectly healthy account.
        rate_limits: {
          available: true,
          entries: [
            { key: 'login:locked:user@example.com', ttl: -2, value: nil, exists: false },
            { key: 'login:attempts:user@example.com', ttl: 900, value: '3', exists: true },
          ],
        },
      },
      findings: [
        { severity: :critical, code: :orphaned_auth_account, message: 'Auth account exists' },
        { severity: :warning, code: :email_drift, message: drift_message },
      ],
    )
  end

  def nothing_found_result
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: nil,
      sections: { customer: { found: false }, auth_account: { available: true, found: false } },
      findings: [{ severity: :critical, code: :not_found, message: 'No customer record' }],
    )
  end

  before do
    # Simple mode: resolve_customer's numeric arm needs no SQL db to return nil.
    allow(Auth::Database).to receive(:connection).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Auth::Operations::Customers::Diagnose).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(orphan_result)
  end

  describe 'identifier threading' do
    # A numeric id belonging to an orphaned account resolves to no Customer, so
    # the raw identifier has to reach the op — it is the only thing left that
    # can find the accounts row.
    it 'passes a numeric account id through with a nil customer' do
      run_cli_command_quietly('customers', 'diagnose', '42')

      expect(Auth::Operations::Customers::Diagnose).to have_received(:new)
        .with(hash_including(identifier: '42', customer: nil))
    end
  end

  describe 'exit code' do
    it 'exits 0 when an orphaned auth account is found' do
      run_cli_command_quietly('customers', 'diagnose', '42')

      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when the identifier resolves to nothing at all' do
      allow(op).to receive(:call).and_return(nothing_found_result)

      run_cli_command_quietly('customers', 'diagnose', 'ghost@example.com')

      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 on an empty identifier' do
      run_cli_command_quietly('customers', 'diagnose', '   ')

      expect(last_exit_code).to eq(1)
    end
  end

  describe 'JSON output' do
    def raw_output(*)
      run_cli_command_quietly('customers', 'diagnose', *)[:stdout]
    end

    def json_output(*)
      JSON.parse(raw_output(*))
    end

    # Obscure-by-default, at every depth — a support transcript or a piped
    # `--json` capture should not carry full addresses unless asked.
    it 'obscures emails in nested sections without --full' do
      payload = json_output('42', '--json')

      expect(payload.dig('sections', 'auth_account', 'email')).to eq('us***@e***.com')
      # String-keyed, two levels down inside decoded audit-log metadata.
      expect(payload.dig('sections', 'audit_log', 'entries', 0, 'metadata', 'email'))
        .to eq('us***@e***.com')
    end

    # Obscuring keyed on `:email`-named fields misses the address the limiter
    # embeds in its KEY. The `login:locked:` prefix has to survive — the key is
    # what an operator pastes into redis-cli.
    it 'obscures the address embedded in limiter keys without --full' do
      raw     = raw_output('42', '--json')
      payload = JSON.parse(raw)

      expect(raw).not_to include('user@example.com')
      expect(payload.dig('sections', 'rate_limits', 'entries', 0, 'key'))
        .to eq('login:locked:us***@e***.com')
      expect(payload.dig('sections', 'rate_limits', 'entries', 1, 'key'))
        .to eq('login:attempts:us***@e***.com')
    end

    # findings never went through the obscuring pass at all.
    it 'obscures the address embedded in finding messages without --full' do
      payload = json_output('42', '--json')
      drift   = payload['findings'].find { |finding| finding['code'] == 'email_drift' }

      expect(drift['message']).to include('(auth side: us***@e***.com)')
      expect(drift['message']).not_to include('user@example.com')
    end

    it 'keeps addresses intact with --full' do
      payload = json_output('42', '--json', '--full')
      drift   = payload['findings'].find { |finding| finding['code'] == 'email_drift' }

      expect(payload.dig('sections', 'auth_account', 'email')).to eq('user@example.com')
      expect(payload.dig('sections', 'rate_limits', 'entries', 0, 'key'))
        .to eq('login:locked:user@example.com')
      expect(drift['message']).to include('(auth side: user@example.com)')
    end

    it 'reports found and the findings list' do
      payload = json_output('42', '--json')

      expect(payload['found']).to be(true)
      expect(payload['findings'].first['code']).to eq('orphaned_auth_account')
    end
  end

  describe 'text output' do
    it 'obscures emails by default, including string-keyed nested ones' do
      output = run_cli_command_quietly('customers', 'diagnose', '42')[:stdout]

      expect(output).to include('us***@e***.com')
      expect(output).not_to include('user@example.com')
    end

    it 'obscures the address embedded in limiter keys and finding messages' do
      output = run_cli_command_quietly('customers', 'diagnose', '42')[:stdout]

      expect(output).not_to include('user@example.com')
      expect(output).to include('login:locked:us***@e***.com')
      expect(output).to include('login:attempts:us***@e***.com')
      expect(output).to include('(auth side: us***@e***.com)')
    end

    it 'prints full addresses with --full' do
      output = run_cli_command_quietly('customers', 'diagnose', '42', '--full')[:stdout]

      expect(output).to include('user@example.com')
      expect(output).to include('login:locked:user@example.com')
      expect(output).to include('(auth side: user@example.com)')
    end
  end
end
