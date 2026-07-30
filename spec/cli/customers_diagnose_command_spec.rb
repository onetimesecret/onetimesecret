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

  # An authdb read that failed: the section renders as `(unavailable: <reason>)`
  # and the reason is free text — a PG error quotes the failing statement, whose
  # WHERE clause carries the email literal.
  def unavailable_section_result
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: nil,
      sections: {
        customer: { found: false },
        auth_account: {
          available: false,
          reason: "PG::ConnectionBad on SELECT * FROM accounts WHERE email = 'dba@example.com'",
        },
      },
      findings: [
        { severity: :critical, code: :authdb_unavailable, message: 'Auth database unavailable' },
      ],
    )
  end

  # Valkey hands back bytes, not text: a truncated multibyte write leaves a
  # field whose encoding is invalid. Obscuring walks every string leaf now, and
  # both String#gsub (all of OT::Utils.obscure_email) and JSON.generate raise on
  # one of those, so a single bad field would take the whole command down.
  #
  # The bad byte sits INSIDE the address in the finding message on purpose: a
  # U+FFFD left there stops EMAIL_PATTERN matching and prints the address in the
  # clear, so obscure_email has to collapse it away (it drops invalid bytes and
  # deletes any marker already present).
  #
  # These are RAW bytes because the op is stubbed here. In production the op
  # scrubs its Result first (Diagnose#utf8_safe_deep, marker mode), so this
  # fixture exercises the adapter's own defense-in-depth scrub rather than the
  # shape the adapter normally sees — see `marked_bytes_result` below for that
  # one, and DiagnoseCommand#obscure for why the adapter keeps a scrub at all.
  def malformed_bytes_result
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: nil,
      sections: {
        customer: { found: false },
        auth_account: {
          available: true,
          found: true,
          account_id: 42,
          status: "verified\xFF",
          email: 'user@example.com',
        },
      },
      findings: [
        { severity: :warning, code: :email_drift, message: "note\xFF us\xFFer@example.com" },
      ],
    )
  end

  # What the op ACTUALLY hands this adapter now: already valid UTF-8, with the
  # corrupt runs marked. The marker sits inside an address again, because that
  # is the combination that printed an address in full two rounds ago.
  def marked_bytes_result
    Auth::Operations::Customers::Diagnose::Result.new(
      customer: nil,
      sections: {
        customer: { found: false },
        auth_account: {
          available: true,
          found: true,
          account_id: 42,
          status: "verified\u{FFFD}",
          email: "us\u{FFFD}er@example.com",
        },
      },
      findings: [
        { severity: :warning, code: :email_drift, message: "note\u{FFFD} us\u{FFFD}er@example.com" },
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

    # The `(unavailable: <reason>)` branch is the only place section text is
    # printed without walking the section's fields, and the reason is the one
    # string in it that carries an address.
    it 'obscures an address quoted in an unavailable section reason' do
      allow(op).to receive(:call).and_return(unavailable_section_result)

      output = run_cli_command_quietly('customers', 'diagnose', '42')[:stdout]

      expect(output).to include(
        "(unavailable: PG::ConnectionBad on SELECT * FROM accounts WHERE email = 'db***@e***.com')",
      )
      expect(output).not_to include('dba@example.com')
    end

    it 'prints the unavailable reason unmasked with --full' do
      allow(op).to receive(:call).and_return(unavailable_section_result)

      output = run_cli_command_quietly('customers', 'diagnose', '42', '--full')[:stdout]

      expect(output).to include(
        "(unavailable: PG::ConnectionBad on SELECT * FROM accounts WHERE email = 'dba@example.com')",
      )
    end
  end

  # A field that is not valid UTF-8 used to reach String#gsub (obscuring every
  # string leaf) and JSON.generate untouched; both raise on it. The bytes are
  # scrubbed at the boundary, so the run completes and the addresses beside
  # them are still masked.
  #
  # The masked path COLLAPSES the bad bytes rather than leaving a marker: a
  # U+FFFD landing inside an address defeats the mask. --full marks instead,
  # because it prints values verbatim and nothing downstream pattern-matches it.
  #
  # The op is stubbed in this group, so it feeds the adapter raw bytes the op
  # would have scrubbed in production. That is the point — it is the only way to
  # exercise the adapter's own scrub — but it means green here says nothing
  # about whether production still reaches that branch. See
  # DiagnoseCommand#obscure.
  describe 'malformed byte sequences' do
    before { allow(op).to receive(:call).and_return(malformed_bytes_result) }

    it 'renders text output without dropping the field or the mask' do
      result = run_cli_command_quietly('customers', 'diagnose', '42')

      expect(result[:stdout]).to include('verified')
      expect(result[:stdout]).to include('note us***@e***.com')
      expect(result[:stdout]).not_to include('user@example.com')
      expect(last_exit_code).to eq(0)
    end

    it 'renders JSON output without --full' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json')[:stdout])

      expect(payload.dig('sections', 'auth_account', 'status')).to eq('verified')
      expect(payload.dig('sections', 'auth_account', 'email')).to eq('us***@e***.com')
    end

    # A bad byte inside the address must not survive as a marker on the masked
    # path — that is what let the whole address through before.
    it 'masks an address whose own bytes are invalid' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json')[:stdout])

      expect(payload['findings'].first['message']).to eq('note us***@e***.com')
      expect(payload['findings'].first['message']).not_to include("\u{FFFD}")
    end

    # --full skips the mask but not the scrub: JSON.generate raises on the raw
    # bytes whether or not anything is being obscured. Here the marker stays,
    # so an operator reading raw values sees where the corruption is.
    it 'renders JSON output with --full' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json', '--full')[:stdout])

      expect(payload.dig('sections', 'auth_account', 'status')).to eq("verified\u{FFFD}")
      expect(payload.dig('sections', 'auth_account', 'email')).to eq('user@example.com')
      expect(payload['findings'].first['message']).to eq("note\u{FFFD} us\u{FFFD}er@example.com")
    end
  end

  # The production hand-off since the op's chokepoint flipped to marker mode:
  # the Result is valid UTF-8 already and carries U+FFFD where the corruption
  # was. The adapter's scrub finds nothing to do, so masking is the ONLY thing
  # standing between a marked address and the terminal.
  describe 'a Result that already carries U+FFFD markers' do
    before { allow(op).to receive(:call).and_return(marked_bytes_result) }

    it 'masks an address whose marker would otherwise defeat the pattern' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json')[:stdout])

      expect(payload.dig('sections', 'auth_account', 'email')).to eq('us***@e***.com')
      expect(payload['findings'].first['message']).to eq('note us***@e***.com')
      expect(payload.to_s).not_to include('user@example.com')
    end

    # The masked path pays for that immunity by losing the marker. That is the
    # accepted trade: --full and the colonel panel keep it.
    it 'drops the corruption marker from non-address text on the masked path' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json')[:stdout])

      expect(payload.dig('sections', 'auth_account', 'status')).to eq('verified')
    end

    it 'keeps the marker under --full' do
      payload = JSON.parse(run_cli_command_quietly('customers', 'diagnose', '42', '--json', '--full')[:stdout])

      expect(payload.dig('sections', 'auth_account', 'status')).to eq("verified\u{FFFD}")
      expect(payload.dig('sections', 'auth_account', 'email')).to eq("us\u{FFFD}er@example.com")
    end
  end
end
