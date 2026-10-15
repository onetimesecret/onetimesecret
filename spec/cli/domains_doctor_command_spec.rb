# spec/cli/domains_doctor_command_spec.rb
#
# frozen_string_literal: true

# Covers `bin/ots domains doctor` after it was rewired to delegate its one
# overlapping repair (check #4, org.domains membership) to
# Onetime::Operations::Domains::Repair, and `bin/ots domains bulk-repair` after
# it became a deprecation shim.
#
# Lives in its own file rather than in domains_command_spec.rb: doctor needs a
# much heavier stub surface (index hashes, org enumeration) than the other
# domain verbs, and the two suites have no shared setup worth merging.

require_relative 'cli_spec_helper'

RSpec.describe 'Domains Doctor Command', type: :cli do
  let(:org_domains) do
    double(
      'OrgDomainsSortedSet',
      to_a: [],
      add: true,
      remove: true,
    )
  end

  let(:organization) do
    double(
      'Organization',
      objid: 'org123',
      org_id: 'org123',
      extid: 'onext123',
      display_name: 'Test Org',
      domains: org_domains,
      domain?: false, # domain is NOT in the collection -> check #4 fires
      list_domains: [],
      add_domain: true,
      archived?: false,
    )
  end

  let(:domain) do
    double(
      'Domain',
      objid: 'obj123',
      domainid: 'obj123',
      identifier: 'obj123',
      extid: 'cdext123',
      display_domain: 'example.com',
      org_id: 'org123',
      verified: 'false',
      txt_validation_value: 'a' * 32,
      created: Time.now.to_i,
      updated: Time.now.to_i,
      save: true,
    )
  end

  let(:orphan) do
    double(
      'OrphanDomain',
      objid: 'obj999',
      domainid: 'obj999',
      identifier: 'obj999',
      extid: 'cdext999',
      display_domain: 'orphan.com',
      org_id: '',
      verified: 'false',
      txt_validation_value: 'b' * 32,
      created: Time.now.to_i,
      updated: Time.now.to_i,
      save: true,
    )
  end

  let(:repaired_result) do
    Onetime::Operations::Domains::Repair::Result.new(
      status: :repaired,
      domain_id: 'obj123',
      extid: 'cdext123',
      display_domain: 'example.com',
      issues: ["org_id is org123 but not in organization's domains collection"],
      repairs_applied: ['Added to organization org123 collection'],
      dry_run: false,
    )
  end

  let(:default_owners_index) do
    index = double('OwnersIndex', hgetall: {}, put: true, remove: true)
    allow(index).to receive(:get) { |domain_id| domain_id == orphan.identifier ? nil : 'org123' }
    index
  end

  let(:canonical_audit_result) do
    Onetime::Operations::Domains::CanonicalIndexAudit::Result.new(rows: [], entries: [], errors: [])
  end

  # Run the command and parse its --json report (the machine-readable shape the
  # rest of this file asserts on).
  def json_report(*)
    JSON.parse(run_cli_command_quietly(*)[:stdout])
  end

  # Index-level checks and the all-orgs sweep are out of scope here; stub them
  # to empty so each example exercises exactly one domain-level check.
  before do
    allow(Onetime::CustomDomain).to receive(:display_domain_index)
      .and_return(double('DisplayDomainIndex', hgetall: {}, remove_field: true, remove: true))
    allow(Onetime::Organization).to receive(:instances).and_return([])
    allow(Onetime::CustomDomain).to receive(:instances).and_return([domain.objid])
    allow(Onetime::CustomDomain).to receive(:load).with(domain.objid).and_return(domain)
    allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
    # owners agrees with org_id by default, so check #10 is silent unless an
    # example says otherwise: 'org123' for the owned doubles, nothing for the
    # orphan (a blank org_id and no entry is agreement, not drift).
    # record_owner is the model's single writer for the index.
    allow(Onetime::CustomDomain).to receive(:owners).and_return(default_owners_index)
    allow(Onetime::CustomDomain).to receive(:record_owner)
    # Check #11 reads the whole keyspace; a clean audit keeps it silent unless
    # an example says otherwise.
    allow(Onetime::Operations::Domains::CanonicalIndexAudit).to receive(:new)
      .and_return(double('CanonicalIndexAudit', call: canonical_audit_result))
  end

  describe 'membership repair delegation' do
    it 'detects the missing membership and mutates nothing without --repair' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)

      output = run_cli_command_quietly('domains', 'doctor', '--all')

      expect(output[:stdout]).to include('not in org.domains sorted set')
      expect(Onetime::Operations::Domains::Repair).not_to have_received(:new)
      expect(org_domains).not_to have_received(:add)
      expect(last_exit_code).to eq(1)
    end

    it 'delegates the repair to the op instead of adding to the sorted set directly' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)
        .and_return(double('RepairOp', call: repaired_result))

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(Onetime::Operations::Domains::Repair).to have_received(:new).with(
        domain: domain,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        dry_run: false,
      )
      # The regression this file exists for: doctor must not touch the sorted
      # set itself, or the cross-org guard and the audit event are bypassed.
      expect(org_domains).not_to have_received(:add)
      expect(output[:stdout]).to include('added to org.domains')
      expect(last_exit_code).to eq(0)
    end

    # Detection passes the domain object to Organization#domain?. A bare objid
    # sent to org.domains.member? never matches: the collection stores raw
    # identifiers and Familia JSON-quotes a String. The real-datastore examples
    # at the end of this file cover the behaviour; this pins the call shape.
    it 'uses the O(1) Organization#domain? test for detection, not the op list_domains path' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)
        .and_return(double('RepairOp', call: repaired_result))

      run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(organization).to have_received(:domain?).with(domain)
      expect(organization).not_to have_received(:list_domains)
    end
  end

  describe 'per-domain failure isolation' do
    let(:second_domain) do
      double(
        'SecondDomain',
        objid: 'obj456',
        domainid: 'obj456',
        identifier: 'obj456',
        extid: 'cdext456',
        display_domain: 'second.com',
        org_id: 'org123',
        verified: 'false',
        txt_validation_value: 'c' * 32,
        created: Time.now.to_i,
        updated: Time.now.to_i,
        save: true,
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:instances).and_return([domain.objid, second_domain.objid])
      allow(Onetime::CustomDomain).to receive(:load).with(second_domain.objid).and_return(second_domain)
    end

    it 'records a cross-org Onetime::Problem as a failed repair and keeps scanning' do
      raising_op = double('RepairOp')
      allow(raising_op).to receive(:call)
        .and_raise(Onetime::Problem, 'Domain example.com already belongs to organization Other Org')
      ok_op      = double('RepairOp', call: repaired_result)

      allow(Onetime::Operations::Domains::Repair).to receive(:new) do |kwargs|
        kwargs[:domain] == domain ? raising_op : ok_op
      end

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(output[:stdout]).to include('Failed repairs:')
      expect(output[:stdout]).to include('already belongs to organization Other Org')
      # The second domain was still visited and repaired.
      expect(Onetime::Operations::Domains::Repair).to have_received(:new).twice
      expect(last_exit_code).to eq(1)
    end

    it 'records a non-repaired op status as a failed repair' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new).and_return(
        double(
          'RepairOp',
          call: Onetime::Operations::Domains::Repair::Result.new(
            status: :org_not_found,
            domain_id: 'obj123',
            extid: 'cdext123',
            display_domain: 'example.com',
            issues: [],
            repairs_applied: [],
            dry_run: false,
          ),
        ),
      )

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(output[:stdout]).to include('repair op returned org_not_found')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'orphaned domain reporting' do
    before do
      allow(Onetime::CustomDomain).to receive(:instances).and_return([orphan.objid])
      allow(Onetime::CustomDomain).to receive(:load).with(orphan.objid).and_return(orphan)
    end

    it 'reports an orphaned domain and points at the repair verb' do
      output = run_cli_command_quietly('domains', 'doctor', '--all')

      expect(output[:stdout]).to include('domain has no org_id (orphaned)')
      expect(output[:stdout]).to include('bin/ots domains repair orphan.com --org-id <ORG>')
      expect(last_exit_code).to eq(1)
    end

    it 'never repairs an orphan, even with --repair' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)

      run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(Onetime::Operations::Domains::Repair).not_to have_received(:new)
      expect(org_domains).not_to have_received(:add)
    end
  end

  # Archive is a soft delete that says nothing about the org's domains, and
  # Organization.load still returns the record — so check #1 (stale_org_reference)
  # sees a healthy pointer while every authorization path that resolves the
  # domain evaluates entitlements against an org the operator believes is gone.
  describe 'archived organization reporting' do
    before do
      allow(organization).to receive(:archived?).and_return(true)
      # The domain IS in the collection, so check #4 stays quiet and this
      # example exercises exactly the archived-org check.
      allow(organization).to receive(:domain?).and_return(true)
    end

    it 'reports the archived owner and points at the manual remedies' do
      output = run_cli_command_quietly('domains', 'doctor', '--all')

      expect(output[:stdout]).to include("org_id 'org123' points to an archived organization")
      expect(output[:stdout]).to include('bin/ots domains transfer example.com --to-org <ORG>')
      expect(last_exit_code).to eq(1)
    end

    it 'never repairs it, even with --repair' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)

      run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(Onetime::Operations::Domains::Repair).not_to have_received(:new)
      expect(org_domains).not_to have_received(:add)
    end
  end

  # Regression guard for the double-count/double-delete bug: doctor used to run
  # two byte-identical passes over Onetime::CustomDomain.display_domain_index
  # (check_display_domain_index_integrity and
  # check_display_domain_index_hash_integrity), so N stale entries were reported
  # as 2N issues at two severities and repaired 2N times.
  describe 'display_domain_index integrity' do
    let(:stale_index) do
      double(
        'DisplayDomainIndex',
        hgetall: { 'stale.example.com' => 'gone999' },
        remove: true,
        remove_field: true,
        release_field: 1,
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(stale_index)
      # No domain-level subjects: this example isolates the index sweep.
      allow(Onetime::CustomDomain).to receive(:instances).and_return([])
      allow(Onetime::CustomDomain).to receive(:load).with('gone999').and_return(nil)
    end

    it 'reports one stale entry exactly once, at high severity' do
      output = run_cli_command_quietly('domains', 'doctor', '--all', '--json')
      report = JSON.parse(output[:stdout])

      index_groups = report['issues'].select { |group| group['type'] == 'indexes' }
      expect(index_groups.size).to eq(1)

      issues = index_groups.first['issues']
      expect(issues.size).to eq(1)
      expect(issues.first['check']).to eq('display_domain_index_stale')
      expect(issues.first['severity']).to eq('high')
      expect(issues.first['total_stale']).to eq(1)

      expect(report['repaired']).to be_empty
      expect(stale_index).not_to have_received(:remove)
      expect(last_exit_code).to eq(1)
    end

    it 'deletes the entry once and records one repair with count 1' do
      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair', '--json')
      report = JSON.parse(output[:stdout])

      expect(report['repaired'].size).to eq(1)
      expect(report['repaired'].first['action']).to eq('display_domain_index_cleaned')
      expect(report['repaired'].first['count']).to eq(1)

      # Ownership-checked: released only while it still names the identifier
      # the scan read, never by a blind HDEL of the field.
      expect(stale_index).to have_received(:release_field).with('stale.example.com', 'gone999').once
      expect(stale_index).not_to have_received(:remove)
      expect(stale_index).not_to have_received(:remove_field)
      expect(last_exit_code).to eq(0)
    end

    it 'records no repair when the entry no longer names that identifier' do
      allow(stale_index).to receive(:release_field).and_return(0)

      report = json_report('domains', 'doctor', '--all', '--repair', '--json')

      expect([report['repaired'], last_exit_code]).to eq([[], 1])
    end

    it 'flags an FQDN mismatch once, not once per pass' do
      mismatched = double('MismatchedDomain', display_domain: 'other.example.com')
      allow(Onetime::CustomDomain).to receive(:load).with('gone999').and_return(mismatched)

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--json')
      report = JSON.parse(output[:stdout])

      issues = report['issues'].find { |group| group['type'] == 'indexes' }['issues']
      expect(issues.size).to eq(1)
      expect(issues.first['stale_entries'].first['reason']).to include('FQDN mismatch')
    end
  end

  # Check #11: canonical_display_domain_index findings from
  # Operations::Domains::CanonicalIndexAudit. Report-only: the writes belong
  # to `bin/ots domains backfill-canonical-index --apply`, run with the
  # application stopped.
  describe 'canonical index integrity' do
    let(:audit_class) { Onetime::Operations::Domains::CanonicalIndexAudit }
    let(:canonical_audit_result) do
      audit_class::Result.new(
        rows: [
          canonical_row(:missing, 'm1'),
          canonical_row(:missing, 'm2'),
          canonical_row(:collision, 'c1'),
          canonical_row(:collision, 'c2'),
          canonical_row(:conflict, 'x1', holder: 'other'),
          canonical_row(:stale, 's1', holder: 'gone'),
          canonical_row(:ok, 'ok1', holder: 'ok1'),
        ],
        entries: [audit_class::Entry.new(category: :stale, canonical: 'orphan.example', holder_id: 'gone2', detail: 'x')],
        errors: [],
      )
    end

    def canonical_row(category, id, holder: nil)
      audit_class::Row.new(
        category: category,
        domain_id: id,
        extid: "cd#{id}",
        display_domain: "#{id}.example",
        canonical: "#{id}.example",
        holder_id: holder,
        org_id: 'org123',
        verification_state: :pending,
        ownership_verified: false,
        verified_by_override: false,
        verified_confirmed_at: nil,
        created: 1_700_000_000,
        detail: nil,
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:instances).and_return([])
    end

    def canonical_issues(report)
      report['issues'].find { |group| group['type'] == 'indexes' }['issues']
        .select { |issue| issue['check'].start_with?('canonical_index_') }
    end

    it 'reports missing, collision, conflict and stale findings with their totals and severities' do
      issues = canonical_issues(json_report('domains', 'doctor', '--all', '--json'))

      expect(issues.to_h { |i| [i['check'], [i['severity'], i['total'], i['repairable']]] }).to eq(
        'canonical_index_missing' => ['high', 2, false],
        'canonical_index_collision' => ['high', 2, false],
        'canonical_index_conflict' => ['high', 1, false],
        'canonical_index_stale' => ['medium', 2, false],
      )
      expect(last_exit_code).to eq(1)
    end

    it 'points at the backfill command and the runbook' do
      issues  = canonical_issues(json_report('domains', 'doctor', '--all', '--json'))
      missing = issues.find { |i| i['check'] == 'canonical_index_missing' }

      expect(missing['repair_action']).to include('backfill-canonical-index --apply', 'custom-domain-canonical-index-backfill.md')
    end

    it 'writes nothing to the canonical index with --repair' do
      index = double('CanonicalIndex')
      allow(Onetime::CustomDomain).to receive(:canonical_display_domain_index).and_return(index)

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(output[:stdout]).to include('no issues are auto-repairable')
      expect(last_exit_code).to eq(2)
    end

    context 'when only unreadable records are found outside instances and the indexes' do
      let(:canonical_audit_result) do
        audit_class::Result.new(
          rows: [],
          entries: [],
          errors: [
            audit_class::Unreadable.new(domain_id: 'broken1', message: 'JSON::ParserError: invalid record'),
            audit_class::Unreadable.new(domain_id: 'broken2', message: 'TypeError: invalid field'),
          ],
        )
      end

      it 'reports identifiers and load errors at high severity as nonrepairable findings' do
        report = json_report('domains', 'doctor', '--all', '--json')

        expect(report.slice('checked', 'healthy', 'repaired', 'failed_repairs')).to eq(
          'checked' => 0, 'healthy' => 0, 'repaired' => [], 'failed_repairs' => [],
        )
        expect(report['issues'].map { |group| group['type'] }).to eq(['indexes'])
        expect(canonical_issues(report)).to contain_exactly(
          include(
            'check' => 'canonical_index_unreadable',
            'severity' => 'high',
            'total' => 2,
            'repairable' => false,
            'examples' => [
              { 'domain_objid' => 'broken1', 'message' => 'JSON::ParserError: invalid record' },
              { 'domain_objid' => 'broken2', 'message' => 'TypeError: invalid field' },
            ],
            'message' => include('2 domain records could not be loaded', 'broken1: JSON::ParserError: invalid record',
              'broken2: TypeError: invalid field'),
            'repair_action' => include('storage_inspect'),
          ),
        )
        expect(last_exit_code).to eq(1)
      end

      it 'includes identifiers and load messages in the text report' do
        output = run_cli_command_quietly('domains', 'doctor', '--all')

        expect(output[:stdout]).to include('[HIGH]', 'broken1: JSON::ParserError: invalid record',
          'broken2: TypeError: invalid field', '[manual fix required]')
        expect(last_exit_code).to eq(1)
      end

      it 'limits examples to ten without losing the total count' do
        errors = (1..12).map do |id|
          audit_class::Unreadable.new(domain_id: "broken#{id}", message: 'TypeError: invalid field')
        end
        result = audit_class::Result.new(rows: [], entries: [], errors: errors)
        allow(audit_class).to receive(:new).and_return(double('CanonicalIndexAudit', call: result))

        issue = canonical_issues(json_report('domains', 'doctor', '--all', '--json')).first

        expect(issue['total']).to eq(12)
        expect(issue['examples'].map { |example| example['domain_objid'] }).to eq((1..10).map { |id| "broken#{id}" })
        expect(last_exit_code).to eq(1)
      end

      it 'exits with manual intervention status and writes nothing with --repair' do
        canonical_index = double('CanonicalIndex')
        display_index = double('DisplayDomainIndex', hgetall: {})
        owners_index = double('OwnersIndex', hgetall: {})
        allow(Onetime::CustomDomain).to receive(:canonical_display_domain_index).and_return(canonical_index)
        allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(display_index)
        allow(Onetime::CustomDomain).to receive(:owners).and_return(owners_index)
        expect(Onetime::CustomDomain).not_to receive(:record_owner)
        expect(Onetime::CustomDomain).not_to receive(:load)
        expect(Onetime::Operations::Domains::Repair).not_to receive(:new)
        expect(domain).not_to receive(:save)
        expect(org_domains).not_to receive(:add)
        expect(org_domains).not_to receive(:remove)

        report = json_report('domains', 'doctor', '--all', '--repair', '--json')

        expect(canonical_issues(report).first['repairable']).to be(false)
        expect(report['repaired']).to be_empty
        expect(report['failed_repairs']).to be_empty
        expect(last_exit_code).to eq(2)
      end

      it 'does not return success when an unrelated index repair succeeds' do
        display_index = double('DisplayDomainIndex', hgetall: { 'stale.example.com' => 'gone999' }, release_field: 1)
        allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(display_index)
        allow(Onetime::CustomDomain).to receive(:load).with('gone999').and_return(nil)

        report = json_report('domains', 'doctor', '--all', '--repair', '--json')

        expect(report['repaired']).to eq([{ 'action' => 'display_domain_index_cleaned', 'count' => 1 }])
        expect(display_index).to have_received(:release_field).with('stale.example.com', 'gone999').once
        expect(canonical_issues(report).first['check']).to eq('canonical_index_unreadable')
        expect(last_exit_code).to eq(2)
      end
    end

    it 'reports a warning when the audit cannot run' do
      allow(audit_class).to receive(:new).and_raise(Redis::CannotConnectError, 'down')

      issues = json_report('domains', 'doctor', '--all', '--json')['issues']
        .find { |group| group['type'] == 'indexes' }['issues']

      expect(issues.map { |i| [i['check'], i['severity']] }).to eq([%w[canonical_index_audit_unavailable warning]])
    end
  end

  describe 'orphan with a stale owners entry' do
    before do
      allow(Onetime::CustomDomain).to receive(:instances).and_return([orphan.objid])
      allow(Onetime::CustomDomain).to receive(:load).with(orphan.objid).and_return(orphan)
      allow(default_owners_index).to receive(:get).and_return('org123')
    end

    # This entry, not the blank org_id, is what blocks org123's deletion.
    it 'flags the entry that still names an org and offers the adoption verb' do
      output = json_report('domains', 'doctor', '--all', '--json')

      issue = output['issues'].flat_map { |group| group['issues'] }
        .find { |i| i['check'] == 'owners_index_drift' }
      expect(issue['message']).to include('orphaned (no org_id)')
      expect(issue['repair_action']).to include('bin/ots domains repair orphan.com --org-id <ORG>')
    end

    it 'removes the entry with --repair, and still assigns no organization' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)

      output = json_report('domains', 'doctor', '--all', '--repair', '--json')

      # A blank target removes the entry; nothing adopts the orphan.
      expect(Onetime::CustomDomain).to have_received(:record_owner).with(orphan, '').once
      expect(Onetime::Operations::Domains::Repair).not_to have_received(:new)

      repaired = output['repaired'].find { |r| r['action'] == 'owners_entry_realigned' }
      expect(repaired['previous_org']).to eq('org123')
      expect(repaired['org']).to eq('')
    end
  end

  # REGRESSION: `bin/ots domains transfer` moved org_id and the org.domains
  # membership but left the CustomDomain.owners entry on the SOURCE org. That
  # entry is the second source of truth for Organization#unlisted_owned_domains,
  # so the source org could never be deleted again — Org::Delete refuses with
  # :drifted_domains, there is no force override, and the refusal advertises
  # THIS command. Doctor must therefore see and fix owners/org_id disagreement.
  describe 'CustomDomain.owners drift' do
    let(:owners_index) do
      double(
        'OwnersIndex',
        hgetall: { 'obj123' => 'oldorg999' },
        get: 'oldorg999',
        put: true,
        remove: true,
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:owners).and_return(owners_index)
    end

    it 'reports the mismatch once, at medium severity, and mutates nothing' do
      output = json_report('domains', 'doctor', '--all', '--json')

      issues = output['issues'].flat_map { |group| group['issues'] }
      drift  = issues.select { |i| %w[owners_index_drift owners_index_stale].include?(i['check']) }

      # Exactly once: the index sweep deliberately skips domains the per-domain
      # scan visits, so N problems never surface as 2N issues.
      expect(drift.size).to eq(1)
      expect(drift.first['check']).to eq('owners_index_drift')
      expect(drift.first['severity']).to eq('medium')
      expect(drift.first['message']).to include('oldorg999')
      expect(drift.first['repairable']).to be(true)

      expect(Onetime::CustomDomain).not_to have_received(:record_owner)
      expect(output['repaired']).to be_empty
      expect(last_exit_code).to eq(1)
    end

    it 'rewrites the entry to match org_id with --repair' do
      output = json_report('domains', 'doctor', '--all', '--repair', '--json')

      # org_id is authoritative; owners is the derived index that follows it.
      expect(Onetime::CustomDomain).to have_received(:record_owner).with(domain, 'org123').once

      repaired = output['repaired'].select { |r| r['action'] == 'owners_entry_realigned' }
      expect(repaired.size).to eq(1)
      expect(repaired.first['org']).to eq('org123')
      expect(repaired.first['previous_org']).to eq('oldorg999')
      expect(last_exit_code).to eq(0)
    end

    it 'reports a missing owners entry, not just a wrong one' do
      allow(owners_index).to receive(:get).and_return(nil)
      allow(owners_index).to receive(:hgetall).and_return({})

      output = json_report('domains', 'doctor', '--all', '--json')

      issue = output['issues'].flat_map { |group| group['issues'] }
        .find { |i| i['check'] == 'owners_index_drift' }
      expect(issue['message']).to include('missing from CustomDomain.owners')
    end

    # The transfer residue itself: the domain now belongs to ANOTHER org, so it
    # is gone from the old org's collection and the per-domain scan never visits
    # it. Only the index sweep can see it, and `doctor --org OLD` is what an
    # operator runs when Org::Delete refuses.
    context 'when the domain was transferred away from the scoped org' do
      let(:moved_domain) do
        double(
          'MovedDomain',
          objid: 'obj777',
          domainid: 'obj777',
          identifier: 'obj777',
          extid: 'cdext777',
          display_domain: 'moved.example.com',
          org_id: 'neworg456',
          save: true,
        )
      end

      before do
        allow(owners_index).to receive(:hgetall).and_return({ 'obj777' => 'org123' })
        allow(Onetime::CustomDomain).to receive(:load).with('obj777').and_return(moved_domain)
        allow(Onetime::Organization).to receive(:find_by_extid).with('onext123').and_return(organization)
      end

      it 'flags the stale entry that blocks the old org deletion' do
        output = json_report('domains', 'doctor', '--org', 'onext123', '--json')

        issue = output['issues'].find { |group| group['type'] == 'indexes' }['issues']
          .find { |i| i['check'] == 'owners_index_stale' }
        expect(issue['severity']).to eq('medium')
        expect(issue['total_stale']).to eq(1)
        expect(issue['stale_entries'].first['domain_id']).to eq('obj777')
        expect(issue['stale_entries'].first['recorded_org_id']).to eq('org123')
        expect(issue['stale_entries'].first['actual_org_id']).to eq('neworg456')
        expect(last_exit_code).to eq(1)
      end

      it 'realigns it with --repair so the old org becomes deletable' do
        output = json_report('domains', 'doctor', '--org', 'onext123', '--repair', '--json')

        expect(Onetime::CustomDomain).to have_received(:record_owner)
          .with('obj777', 'neworg456').once

        repaired = output['repaired'].select { |r| r['action'] == 'owners_index_realigned' }
        expect(repaired.size).to eq(1)
        expect(repaired.first['count']).to eq(1)
      end

      it 'removes the entry outright when the domain record is gone' do
        allow(Onetime::CustomDomain).to receive(:load).with('obj777').and_return(nil)

        output = json_report('domains', 'doctor', '--org', 'onext123', '--repair', '--json')

        # nil target: the single writer deletes rather than writing an empty
        # value, which would linger in every future HGETALL scan.
        expect(Onetime::CustomDomain).to have_received(:record_owner).with('obj777', nil).once
        expect(output['repaired'].first['action']).to eq('owners_index_realigned')
      end
    end
  end

  describe 'json report shape' do
    it 'carries checked/healthy/issues/repaired plus failed_repairs' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)
        .and_return(double('RepairOp', call: repaired_result))

      output = run_cli_command_quietly('domains', 'doctor', '--all', '--repair', '--json')
      report = JSON.parse(output[:stdout])

      expect(report.keys).to include('checked', 'healthy', 'issues', 'repaired', 'failed_repairs')
      expect(report['checked']).to eq(1)
      expect(report['repaired'].first['action']).to eq('added_to_org_domains')
      expect(report['failed_repairs']).to be_empty
    end
  end

  describe 'bulk-repair deprecation shim' do
    it 'prints the replacement command and exits non-zero' do
      output = run_cli_command_quietly('domains', 'bulk-repair')

      expect(output[:stderr]).to include('bin/ots domains doctor --all --repair')
      expect(last_exit_code).to eq(1)
    end

    it 'still exits non-zero when invoked with the old --force flag' do
      output = run_cli_command_quietly('domains', 'bulk-repair', '--force')

      expect(output[:stderr]).to include('has been removed')
      expect(last_exit_code).to eq(1)
    end

    # The old command walked every custom domain in the install and mutated org
    # collections with no audit trail. The shim must stay inert — if someone
    # reintroduces mutation here it bypasses Operations::Domains::Repair again.
    it 'mutates nothing, even when handed the old --force flag' do
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:add_domain)

      run_cli_command_quietly('domains', 'bulk-repair', '--force')

      expect(organization).not_to have_received(:add_domain)
    end
  end
end

# org.domains is a Familia participation collection: it stores raw domain
# identifiers, and Familia sends a bare String argument JSON-quoted. A
# `member?`, `score` or `remove` given a String objid therefore never matches
# an entry. The doubles above cannot see that, so these examples run the
# checks against the real datastore.
#
# Deliberately NOT `type: :cli`: that hook (cli_spec_helper.rb) mocks
# Familia.dbclient. The examples drive the check methods directly, the same
# way org_doctor_command_spec.rb does.
RSpec.describe 'Domains Doctor Command collection checks (real datastore)', :datastore do
  let(:suffix) { "#{Familia.now.to_i}#{SecureRandom.hex(4)}" }
  let(:command) { Onetime::CLI::DomainsDoctorCommand.new }
  let(:report) { { checked: 0, healthy: 0, issues: [], repaired: [], failed_repairs: [] } }

  before do
    @customers = []
    @orgs      = []
    @domains   = []
  end

  after do
    @domains.each do |domain|
      domain.destroy! if domain.exists?
    rescue StandardError => ex
      warn "[domains doctor spec] domain cleanup failed: #{ex.class}: #{ex.message}"
    end
    @orgs.each do |org|
      # A failing example can leave an entry behind, and destroy! refuses an
      # org whose collection is not empty.
      org.domains.delete!
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[domains doctor spec] org cleanup failed: #{ex.class}: #{ex.message}"
    end
    @customers.each do |cust|
      cust.destroy! if cust.exists?
    rescue StandardError => ex
      warn "[domains doctor spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def create_org(label)
    owner = Onetime::Customer.create!(email: "domains_doctor_#{label}_#{suffix}@onetimesecret.com")
    @customers << owner
    org = Onetime::Organization.create!("Domains Doctor #{label} #{suffix}", owner)
    @orgs << org
    org
  end

  # create! lists the domain in org.domains and writes CustomDomain.owners.
  def create_domain(org, label)
    domain = Onetime::CustomDomain.create!("#{label}-#{suffix}.example.com", org.objid)
    @domains << domain
    domain
  end

  def all_issues
    report[:issues].flat_map { |group| group[:issues] }
  end

  describe 'check #4 (domain is in org.domains)' do
    it 'does not flag a domain that is in its organization collection' do
      org    = create_org('listed')
      domain = create_domain(org, 'listed')
      expect(org.domains.to_a).to include(domain.objid)

      issues = []
      command.send(:check_org_domains_membership, domain, issues, report, repair: false)

      expect(issues).to be_empty
    end
  end

  describe 'check #5 repair (stale org.domains entries)' do
    it 'removes an entry whose domain record is gone and counts it' do
      org   = create_org('stale')
      ghost = Onetime::CustomDomain.new(objid: "ghost#{suffix}")
      org.domains.add(ghost, Familia.now.to_f)
      expect(org.domains.to_a).to include(ghost.objid)

      command.send(:check_stale_org_domains, org, report, repair: true)

      expect(org.domains.to_a).not_to include(ghost.objid)
      repaired = report[:repaired].select { |r| r[:action] == :stale_org_domains_removed }
      expect(repaired.size).to eq(1)
      expect(repaired.first[:count]).to eq(1)
    end

    it 'removes an entry for a domain that belongs to another organization' do
      org_a  = create_org('a')
      org_b  = create_org('b')
      domain = create_domain(org_b, 'elsewhere')
      domain.add_to_organization_domains(org_a)
      expect(org_a.domains.to_a).to include(domain.objid)

      command.send(:check_stale_org_domains, org_a, report, repair: true)

      expect(org_a.domains.to_a).not_to include(domain.objid)
      expect(org_b.domains.to_a).to include(domain.objid)
      # The domain's reverse index follows, so add_domain's cross-org guard
      # (organization_instances) no longer sees org_a.
      expect(domain.organization_instances.map(&:objid)).to eq([org_b.objid])
      expect(report[:repaired].find { |r| r[:action] == :stale_org_domains_removed }[:count]).to eq(1)
    end

    it 'counts only the entries it removed' do
      org   = create_org('raced')
      ghost = Onetime::CustomDomain.new(objid: "ghost#{suffix}")
      org.domains.add(ghost, Familia.now.to_f)

      # Another process removes the entry after detection read it.
      allow(Onetime::CustomDomain).to receive(:load).and_wrap_original do |original, objid|
        org.domains.remove(ghost) if objid == ghost.objid
        original.call(objid)
      end

      command.send(:check_stale_org_domains, org, report, repair: true)

      expect(report[:issues].size).to eq(1)
      expect(report[:repaired]).to be_empty
    end
  end

  describe 'check #10 sweep under --org' do
    [false, true].each do |repair|
      context "with repair=#{repair}" do
        it 'reports owners drift for a valid listed domain once' do
          org    = create_org('owners')
          domain = create_domain(org, 'drifted')
          recorded_org_id = "other#{suffix}"
          Onetime::CustomDomain.record_owner(domain, recorded_org_id)

          # The --org branch of #call.
          command.send(:check_index_integrity, report, repair: repair, scope_org: org)
          command.send(:check_org_domains, org, report, repair: repair)

          drift = all_issues.select { |i| %i[owners_index_drift owners_index_stale].include?(i[:check]) }
          expect(drift.map { |i| i[:check] }).to eq([:owners_index_drift])
          expect(report[:checked]).to eq(1)
          expect(Onetime::CustomDomain.owners.get(domain.objid)).to eq(repair ? org.objid : recorded_org_id)
          repaired = report[:repaired].select { |r| r[:action] == :owners_entry_realigned }
          expect(repaired.size).to eq(repair ? 1 : 0)
        end

        it 'reports a missing record even while its ID is listed in the scoped org' do
          org   = create_org('missing_owner')
          ghost = Onetime::CustomDomain.new(objid: "ghost#{suffix}")
          org.domains.add(ghost, Familia.now.to_f)
          Onetime::CustomDomain.record_owner(ghost, org.objid)
          expect(org.domain?(ghost.objid)).to be(true)

          command.send(:check_index_integrity, report, repair: repair, scope_org: org)
          command.send(:check_org_domains, org, report, repair: repair)

          drift = all_issues.select { |i| %i[owners_index_drift owners_index_stale].include?(i[:check]) }
          expect(drift.map { |i| i[:check] }).to eq([:owners_index_stale])
          expect(drift.first[:stale_entries]).to eq([{
            domain_id: ghost.objid,
            recorded_org_id: org.objid,
            actual_org_id: nil,
            reason: 'domain record not found',
          }])
          expect(report[:checked]).to eq(0)
          expect(org.domain?(ghost.objid)).to eq(!repair)
          expect(Onetime::CustomDomain.owners.get(ghost.objid)).to eq(repair ? nil : org.objid)
          repaired = report[:repaired].select { |r| r[:action] == :owners_index_realigned }
          expect(repaired.map { |r| r[:count] }).to eq(repair ? [1] : [])
        ensure
          Onetime::CustomDomain.record_owner(ghost, nil) if ghost
        end

        it 'handles owners drift for a listed domain that belongs to another org once' do
          org_a  = create_org('old_owner')
          org_b  = create_org('actual_owner')
          domain = create_domain(org_b, 'transferred')
          domain.add_to_organization_domains(org_a)
          Onetime::CustomDomain.record_owner(domain, org_a.objid)
          expect(org_a.domain?(domain.objid)).to be(true)

          command.send(:check_index_integrity, report, repair: repair, scope_org: org_a)
          command.send(:check_org_domains, org_a, report, repair: repair)

          drift = all_issues.select { |i| %i[owners_index_drift owners_index_stale].include?(i[:check]) }
          expect(drift.map { |i| i[:check] }).to eq([repair ? :owners_index_stale : :owners_index_drift])
          expect(report[:checked]).to eq(repair ? 0 : 1)
          expect(org_a.domain?(domain.objid)).to eq(!repair)
          expect(org_b.domain?(domain.objid)).to be(true)
          expect(Onetime::CustomDomain.load(domain.objid).org_id).to eq(org_b.objid)
          expect(Onetime::CustomDomain.owners.get(domain.objid)).to eq(repair ? org_b.objid : org_a.objid)
          repaired = report[:repaired].select { |r| r[:action] == :owners_index_realigned }
          expect(repaired.map { |r| r[:count] }).to eq(repair ? [1] : [])
          expect(org_a.unlisted_owned_domains).to be_empty
        end
      end
    end
  end
end
