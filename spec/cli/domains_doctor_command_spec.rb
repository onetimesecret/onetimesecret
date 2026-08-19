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
      member?: false, # domain is NOT in the collection -> check #4 fires
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

  # Index-level checks and the all-orgs sweep are out of scope here; stub them
  # to empty so each example exercises exactly one domain-level check.
  before do
    allow(Onetime::CustomDomain).to receive(:display_domain_index)
      .and_return(double('DisplayDomainIndex', hgetall: {}, remove_field: true, remove: true))
    allow(Onetime::Organization).to receive(:instances).and_return([])
    allow(Onetime::CustomDomain).to receive(:instances).and_return([domain.objid])
    allow(Onetime::CustomDomain).to receive(:load).with(domain.objid).and_return(domain)
    allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
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

    it 'uses the O(1) member? test for detection, not the op list_domains path' do
      allow(Onetime::Operations::Domains::Repair).to receive(:new)
        .and_return(double('RepairOp', call: repaired_result))

      run_cli_command_quietly('domains', 'doctor', '--all', '--repair')

      expect(org_domains).to have_received(:member?).with(domain.objid)
      expect(organization).not_to have_received(:list_domains)
    end
  end

  describe 'per-domain failure isolation' do
    let(:second_domain) do
      double(
        'SecondDomain',
        objid: 'obj456',
        domainid: 'obj456',
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
      allow(org_domains).to receive(:member?).and_return(true)
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

      # Canonical delete: lib/onetime/models/custom_domain.rb uses .remove on
      # display_domain_index. (.remove_field is an alias of the same HashKey
      # method, so this pins the form, not the behaviour.)
      expect(stale_index).to have_received(:remove).with('stale.example.com').once
      expect(stale_index).not_to have_received(:remove_field)
      expect(last_exit_code).to eq(0)
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
