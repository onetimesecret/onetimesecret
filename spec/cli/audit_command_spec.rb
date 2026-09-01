# spec/cli/audit_command_spec.rb
#
# frozen_string_literal: true

# CLI reader for the operator audit trail (#4334).
#
# The command is deliberately thin over Onetime::ColonelAuditReader — the same
# merge, filters and field allowlist the HTTP surfaces use — so these cover the
# CLI's own job: format selection, filter pass-through, and the read-only
# guarantee. What the shared reader emits is pinned in
# spec/integration/all/colonel_observability_spec.rb and the model tryout.
#
# Run: pnpm run test:rspec spec/cli/audit_command_spec.rb

require_relative 'cli_spec_helper'
require 'csv'

RSpec.describe 'audit CLI commands', type: :cli do
  before do
    Onetime::ColonelAuditEvent.events.clear
    Onetime::ColonelAuditEvent.security_events.clear
    Onetime::ColonelAuditEvent.access_events.clear
  end

  after do
    Onetime::ColonelAuditEvent.events.clear
    Onetime::ColonelAuditEvent.security_events.clear
    Onetime::ColonelAuditEvent.access_events.clear
  end

  def record(actor: 'ur_colonel1', verb: 'customer.purge', target: 'ur_victim', detail: nil)
    Onetime::ColonelAuditEvent.record(
      actor: actor, verb: verb, target: target, result: :success, detail: detail,
    )
  end

  describe 'ots audit' do
    it 'prints usage and the retained counts' do
      record
      Onetime::ColonelAuditEvent.record_security(
        actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure,
      )

      output = run_cli_command_quietly('audit')

      expect(output[:stdout]).to include('Operator audit trail')
      expect(output[:stdout]).to include('1 operator, 1 security telemetry, 0 observation')
      expect(output[:stdout]).to include('ots audit <subcommand>')
    end
  end

  describe 'ots audit list' do
    it 'renders a human-readable table newest-first' do
      record(verb: 'customer.purge')
      record(verb: 'organization.delete', target: 'on_org1')

      output = run_cli_command_quietly('audit', 'list')

      expect(output[:stdout]).to include('When (UTC)', 'Actor', 'Verb', 'Target', 'Result')
      verbs = output[:stdout].scan(/customer\.purge|organization\.delete/)
      expect(verbs).to eq(%w[organization.delete customer.purge])
    end

    it 'says so plainly when the trail is empty' do
      output = run_cli_command_quietly('audit', 'list')

      expect(output[:stdout]).to include('No audit events recorded.')
    end

    it 'emits CSV with the same allowlisted header as the export endpoint' do
      record(detail: { 'reason' => 'gdpr' })

      output = run_cli_command_quietly('audit', 'list', '--format', 'csv')
      rows   = CSV.parse(output[:stdout])

      expect(rows.first).to eq(Onetime::ColonelAuditReader::FIELDS.map(&:to_s))
      expect(JSON.parse(rows[1][5])).to eq('reason' => 'gdpr')
    end

    it 'emits one JSON object per line for ndjson' do
      record(verb: 'customer.purge')
      record(verb: 'session.delete')

      output = run_cli_command_quietly('audit', 'list', '--format', 'ndjson')
      lines  = output[:stdout].lines.map { |line| JSON.parse(line) }

      expect(lines.map { |e| e['verb'] }).to eq(%w[session.delete customer.purge])
    end

    it 'emits a pretty JSON array for json' do
      record(verb: 'customer.purge')

      output = run_cli_command_quietly('audit', 'list', '--format', 'json')

      expect(JSON.parse(output[:stdout]).map { |e| e['verb'] }).to eq(%w[customer.purge])
    end

    it 'passes --verb through as an exact-or-category filter' do
      record(verb: 'customer.purge')
      record(verb: 'session.delete')

      output = run_cli_command_quietly('audit', 'list', '--verb', 'customer', '--format', 'ndjson')

      expect(output[:stdout].lines.map { |l| JSON.parse(l)['verb'] }).to eq(%w[customer.purge])
    end

    it 'passes --actor through as a case-insensitive substring filter' do
      record(actor: 'ur_alice123', verb: 'v.alice')
      record(actor: 'ur_bob456', verb: 'v.bob')

      output = run_cli_command_quietly('audit', 'list', '--actor', 'ALICE', '--format', 'ndjson')

      expect(output[:stdout].lines.map { |l| JSON.parse(l)['actor'] }).to eq(%w[ur_alice123])
    end

    it 'honours --limit, keeping the newest' do
      3.times { |i| record(verb: "v#{i}") }

      output = run_cli_command_quietly('audit', 'list', '--limit', '1', '--format', 'ndjson')

      expect(output[:stdout].lines.map { |l| JSON.parse(l)['verb'] }).to eq(%w[v2])
    end

    it 'merges the security-telemetry trail into the same feed' do
      record(verb: 'customer.purge')
      Onetime::ColonelAuditEvent.record_security(
        actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure,
      )

      output = run_cli_command_quietly('audit', 'list', '--format', 'ndjson')

      expect(output[:stdout].lines.map { |l| JSON.parse(l)['verb'] })
        .to contain_exactly('customer.purge', 'auth.throttled')
    end

    it 'refuses an unknown format instead of silently defaulting' do
      run_cli_command_quietly('audit', 'list', '--format', 'xlsx')

      expect(last_exit_code).to eq(1)
    end

    # CONTRACT 4, first half: reading the trail must never append to the
    # OPERATOR trail — including from a shell, where an accidental self-audit
    # would be invisible until it had evicted real records.
    it 'writes NO audit event to the OPERATOR trail' do
      record
      before_count = Onetime::ColonelAuditEvent.count

      run_cli_command_quietly('audit', 'list')
      run_cli_command_quietly('audit', 'list', '--format', 'csv', '--verb', 'customer')

      expect(Onetime::ColonelAuditEvent.count).to eq(before_count)
    end

    # Second half (#4335). A shell read is exactly the access that would
    # otherwise be invisible, so it is recorded — on the budgeted access trail,
    # attributed to the CLI sentinel because a shell carries no colonel
    # identity (ADR-023: never fabricate an actor).
    it 'records ONE observation per invocation, attributed to the CLI sentinel' do
      record

      run_cli_command_quietly('audit', 'list')

      expect(Onetime::ColonelAuditEvent.access_count).to eq(1)
      event = Onetime::ColonelAuditEvent.recent_access(1).first
      expect(event['verb']).to eq('audit.list')
      expect(event['actor']).to eq('cli')
      expect(event['target']).to eq('colonel_audit')
      expect(event['detail']).to include('source' => 'cli', 'format' => 'text', 'returned' => 1)
    end

    # A redirected csv/ndjson run IS the CLI's export path, so it records the
    # bulk verb the HTTP download uses, not the page-view one.
    it 'records a csv/ndjson run as audit.export, not audit.list' do
      record

      run_cli_command_quietly('audit', 'list', '--format', 'ndjson')

      event = Onetime::ColonelAuditEvent.recent_access(1).first
      expect(event['verb']).to eq('audit.export')
      expect(event['detail']).to include('format' => 'ndjson')
    end

    # Recorded after the output, so a redirected export file never contains the
    # event describing its own creation.
    it 'never includes its own observation in the output it just produced' do
      output = run_cli_command_quietly('audit', 'list', '--format', 'ndjson')

      expect(output[:stdout]).to eq('')
      expect(Onetime::ColonelAuditEvent.access_count).to eq(1)
    end

    it 'records nothing when the format is rejected: the read never happened' do
      run_cli_command_quietly('audit', 'list', '--format', 'xlsx')

      expect(Onetime::ColonelAuditEvent.access_count).to eq(0)
    end
  end
end
