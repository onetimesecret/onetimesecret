# spec/cli/domains_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Domains Command', type: :cli do
  let(:organization) do
    owner = double('Owner', email: 'owner@example.com')
    double('Organization',
      org_id: 'org123',
      display_name: 'Test Org',
      list_domains: ['example.com'],
      add_domain: true,
      remove_domain: true,
      owner: owner,
      member_count: 5
    )
  end

  let(:domain) do
    double('Domain',
      domainid: 'example.com',
      domain_name: 'example.com',
      display_domain: 'example.com',
      base_domain: 'example.com',
      subdomain: nil,
      tld: 'com',
      sld: 'example',
      trd: nil,
      org_id: 'org123',
      verified: 'true',
      verification_state: 'verified',
      resolving: 'false',
      status: 'active',
      txt_validation_host: '_onetimesecret.example.com',
      txt_validation_value: 'v=lettermint',
      validation_record: 'TXT',
      vhost: 'example.com',
      parse_vhost: { 'host' => 'example.com' },
      allow_public_homepage?: false,
      allow_public_api?: false,
      apex?: true,
      objid: 'obj123',
      extid: 'ext123',
      dbkey: 'domain:example.com',
      updated: Time.now.to_i,
      created: Time.now.to_i,
      save: true,
      primary_organization: organization,
      'updated=': nil,
      'org_id=': nil
    )
  end

  before do
    allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([domain.domainid])
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(domain)
    allow(Onetime::Organization).to receive(:load).and_return(organization)
  end

  describe 'without subcommand' do
    it 'lists all domains by default' do
      output = run_cli_command_quietly('domains')
      expect(output[:stdout]).to include('custom domains')
    end
  end

  describe 'info subcommand' do
    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'info')
      expect(output[:stderr]).to include('was called with no arguments')
    end

    it 'displays domain information' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)

      output = run_cli_command_quietly('domains', 'info', 'example.com')
      expect(output[:stdout]).to include('Domain Information')
      expect(output[:stdout]).to include('example.com')
    end

    it 'handles non-existent domain' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('notfound.com').and_return(nil)

      output = run_cli_command_quietly('domains', 'info', 'notfound.com')
      expect(output[:stdout]).to include('not found')
    end
  end

  describe 'transfer subcommand' do
    # The transfer verb now delegates to Onetime::Operations::Domains::Transfer
    # (the single toolbox impl the colonel endpoint also calls). The CLI owns
    # only resolution, confirmation/dry-run, and output — so the op is stubbed
    # and the command's own contract (statuses, exit codes, --json) is asserted.
    def transfer_result(status:, dry_run: false, from_org_id: 'org123')
      double('TransferResult',
        status: status, domain_id: 'example.com', extid: 'ext123',
        display_domain: 'example.com', from_org_id: from_org_id, from_org_name: 'Old Org',
        to_org_id: 'org456', to_org_name: 'New Org', dry_run: dry_run)
    end

    def stub_transfer(result)
      op = double('Transfer', call: result)
      allow(Onetime::Operations::Domains::Transfer).to receive(:new).and_return(op)
      op
    end

    before do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
    end

    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'transfer')
      expect(output[:stderr]).to include('was called with no arguments')
    end

    it 'requires --to-org option' do
      output = run_cli_command_quietly('domains', 'transfer', 'example.com')
      expect(output[:stderr]).to include('missing keyword: :to_org')
    end

    it 'transfers domain between organizations with --yes' do
      stub_transfer(transfer_result(status: :transferred))

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--yes')
      expect(output[:stdout]).to include('Transfer complete')
      expect(last_exit_code).to eq(0)
    end

    it 'emits the Result shape with --yes --json' do
      stub_transfer(transfer_result(status: :transferred))

      output  = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--yes', '--json')
      payload = JSON.parse(output[:stdout])
      expect(payload['status']).to eq('transferred')
      expect(payload['to_org_id']).to eq('org456')
      expect(last_exit_code).to eq(0)
    end

    it 'refuses --json without --yes or --dry-run' do
      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('--yes')
      expect(last_exit_code).to eq(1)
    end

    it 'keeps a raised apply failure machine-readable under --json' do
      op = double('Transfer')
      allow(op).to receive(:call).and_raise(StandardError, 'datastore unavailable')
      allow(Onetime::Operations::Domains::Transfer).to receive(:new).and_return(op)

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--yes', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('datastore unavailable')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 on an ownership :mismatch' do
      stub_transfer(transfer_result(status: :mismatch))

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--yes')
      expect(output[:stdout]).to include('does not match')
      expect(last_exit_code).to eq(1)
    end

    it '--dry-run previews without mutating' do
      stub_transfer(transfer_result(status: :planned, dry_run: true))

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--dry-run')
      expect(output[:stdout]).to include('Dry run')
      expect(last_exit_code).to eq(0)
    end

    it 'is reachable through the reassign alias' do
      stub_transfer(transfer_result(status: :transferred))

      output = run_cli_command_quietly('domains', 'reassign', 'example.com', '--to-org', 'org456', '--yes')
      expect(output[:stdout]).to include('Transfer complete')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'remove subcommand' do
    def remove_result(status:, dry_run:, reasserts: false)
      double('RemoveResult',
        status: status, domain_id: 'example.com', extid: 'ext123',
        display_domain: 'example.com', org_id: 'org123', org_name: 'Test Org',
        reasserts_survivor: reasserts, dry_run: dry_run)
    end

    before do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
    end

    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'remove')
      expect(output[:stderr]).to include('was called with no arguments')
    end

    it 'previews (dry-run) then applies after confirmation — two op calls' do
      op = double('Remove')
      allow(op).to receive(:call).and_return(
        remove_result(status: :planned, dry_run: true, reasserts: true),
        remove_result(status: :removed, dry_run: false, reasserts: true),
      )
      allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('domains', 'remove', 'example.com')
      expect(output[:stdout]).to include('Removal Details')
      expect(output[:stdout]).to include('SHADOW record')
      expect(output[:stdout]).to include('Removal complete')
      expect(last_exit_code).to eq(0)
    end

    it '--apply skips the prompt' do
      op = double('Remove', call: remove_result(status: :removed, dry_run: false))
      allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)

      output = run_cli_command_quietly('domains', 'remove', 'example.com', '--apply')
      expect(output[:stdout]).to include('Removal complete')
      expect(last_exit_code).to eq(0)
    end

    it '--dry-run previews and never applies' do
      op = double('Remove', call: remove_result(status: :planned, dry_run: true))
      allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)

      output = run_cli_command_quietly('domains', 'remove', 'example.com', '--dry-run')
      expect(output[:stdout]).to include('Dry run')
      expect(last_exit_code).to eq(0)
    end

    it 'refuses --json without --apply' do
      output = run_cli_command_quietly('domains', 'remove', 'example.com', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('--apply')
      expect(last_exit_code).to eq(1)
    end

    it 'keeps a raised apply failure machine-readable under --json' do
      op = double('Remove')
      allow(op).to receive(:call).and_raise(StandardError, 'datastore unavailable')
      allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)

      output = run_cli_command_quietly('domains', 'remove', 'example.com', '--apply', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('datastore unavailable')
      expect(last_exit_code).to eq(1)
    end

    it 'aborts without applying when the operator declines' do
      op = double('Remove', call: remove_result(status: :planned, dry_run: true))
      allow(Onetime::Operations::Domains::Remove).to receive(:new).and_return(op)
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('domains', 'remove', 'example.com')
      expect(output[:stdout]).to include('Aborted.')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'verify subcommand' do
    def verify_result
      double('VerifyResult',
        domain: domain, success?: true, dns_validated: true, ssl_ready: true,
        is_resolving: true, previous_state: :pending, current_state: :verified,
        changed?: true, persisted: true, error: nil,
        to_h: { current_state: :verified, dns_validated: true })
    end

    it 'errors without a domain or --all' do
      output = run_cli_command_quietly('domains', 'verify')
      expect(output[:stdout]).to include('Provide a domain name or use --all')
      expect(last_exit_code).to eq(1)
    end

    it 'verifies a single domain through the ADMIN op (audited)' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      op = double('AdminVerify', call: verify_result)
      expect(Onetime::Operations::AdminVerifyDomain).to receive(:new)
        .with(hash_including(domain: domain, persist: true)).and_return(op)

      output = run_cli_command_quietly('domains', 'verify', 'example.com')
      expect(output[:stdout]).to include('Domain Verification: example.com')
      expect(output[:stdout]).to include('DNS Validated:    yes')
      expect(last_exit_code).to eq(0)
    end

    it '--dry-run runs the admin op with persist:false' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(domain).to receive(:primary_organization).and_return(organization)
      allow(Onetime::CustomDomain::HomepageConfig).to receive(:find_by_domain_id).and_return(nil)
      op = double('AdminVerify', call: verify_result)
      expect(Onetime::Operations::AdminVerifyDomain).to receive(:new)
        .with(hash_including(persist: false)).and_return(op)

      run_cli_command_quietly('domains', 'verify', 'example.com', '--dry-run')
      expect(last_exit_code).to eq(0)
    end

    it 'emits JSON for a single domain' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      op = double('AdminVerify', call: verify_result)
      allow(Onetime::Operations::AdminVerifyDomain).to receive(:new).and_return(op)

      output  = run_cli_command_quietly('domains', 'verify', 'example.com', '--json')
      payload = JSON.parse(output[:stdout])
      expect(payload['dry_run']).to be(false)
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when the domain cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('notfound.com').and_return(nil)

      output = run_cli_command_quietly('domains', 'verify', 'notfound.com')
      expect(output[:stdout]).to include('Domain not found: notfound.com')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects a non-positive --limit in bulk mode instead of crashing on take(-1)' do
      output = run_cli_command_quietly('domains', 'verify', '--all', '--limit', '-1')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end

    it 'reports a rejected --limit as JSON under --json' do
      output = run_cli_command_quietly('domains', 'verify', '--all', '--limit', '0', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('--limit')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects --limit in single mode instead of silently ignoring it' do
      expect(Onetime::Operations::AdminVerifyDomain).not_to receive(:new)

      output = run_cli_command_quietly('domains', 'verify', 'example.com', '--limit', '-1')
      expect(output[:stdout]).to include('Bulk-mode options require --all: --limit')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects the bulk filters in single mode, naming each one' do
      output = run_cli_command_quietly(
        'domains', 'verify', 'example.com', '--orphaned', '--org-id', 'org123', '--rate-limit', '2.0'
      )
      expect(output[:stdout]).to include('--rate-limit')
      expect(output[:stdout]).to include('--orphaned')
      expect(output[:stdout]).to include('--org-id')
      expect(last_exit_code).to eq(1)
    end

    it 'reports rejected bulk-mode options as JSON under --json' do
      output = run_cli_command_quietly('domains', 'verify', 'example.com', '--unverified', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('--unverified')
      expect(last_exit_code).to eq(1)
    end

    it 'still verifies a single domain when only mode-agnostic flags are given' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(domain).to receive_messages(primary_organization: organization, identifier: 'example.com')
      allow(Onetime::CustomDomain::HomepageConfig).to receive(:find_by_domain_id).and_return(nil)
      op = double('AdminVerify', call: verify_result)
      allow(Onetime::Operations::AdminVerifyDomain).to receive(:new).and_return(op)

      run_cli_command_quietly('domains', 'verify', 'example.com', '--dry-run', '--json')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'list subcommand' do
    let(:rows) do
      [
        { domain_id: 'example.com', display_domain: 'example.com', org_id: 'org123',
          org_name: 'Test Org', verified: true, verification_state: 'verified', created: 1, updated: 2 },
        { domain_id: 'orphan.com', display_domain: 'orphan.com', org_id: '',
          org_name: 'Unknown', verified: false, verification_state: 'pending', created: 1, updated: 2 },
      ]
    end

    def stub_list(returned_rows)
      op = double('List', call: double('ListResult', domains: returned_rows))
      allow(Onetime::Operations::Domains::List).to receive(:new).and_return(op)
      op
    end

    it 'lists all domains via the shared op' do
      stub_list(rows)

      output = run_cli_command_quietly('domains', 'list')
      expect(output[:stdout]).to include('2 custom domains')
      expect(output[:stdout]).to include('example.com')
      expect(last_exit_code).to eq(0)
    end

    it 'drives the op in unpaginated (per_page: nil) CLI mode' do
      op = double('List', call: double('ListResult', domains: rows))
      expect(Onetime::Operations::Domains::List).to receive(:new)
        .with(hash_including(per_page: nil)).and_return(op)

      run_cli_command_quietly('domains', 'list')
      expect(last_exit_code).to eq(0)
    end

    it 'filters orphaned domains client-side' do
      stub_list(rows)

      output = run_cli_command_quietly('domains', 'list', '--orphaned')
      expect(output[:stdout]).to include('1 custom domains')
      expect(output[:stdout]).to include('orphan.com')
    end

    it 'emits JSON' do
      stub_list(rows)

      output  = run_cli_command_quietly('domains', 'list', '--json')
      payload = JSON.parse(output[:stdout])
      expect(payload['count']).to eq(2)
      expect(last_exit_code).to eq(0)
    end

    it 'rejects a non-positive --limit instead of crashing on first(-1)' do
      stub_list(rows)

      output = run_cli_command_quietly('domains', 'list', '--limit', '-1')
      expect(output[:stdout]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end

    it 'groups duplicate display_domain records (the shadow-record diagnostic)' do
      dupes = [
        { domain_id: 'a1', display_domain: 'dup.com', org_id: 'org123', org_name: 'Test Org',
          verified: true, verification_state: 'verified', created: 1, updated: 2 },
        { domain_id: 'a2', display_domain: 'dup.com', org_id: '', org_name: 'Unknown',
          verified: false, verification_state: 'pending', created: 1, updated: 2 },
      ]
      stub_list(dupes)

      output = run_cli_command_quietly('domains', 'list')
      expect(output[:stdout]).to include('dup.com (2 records)')
      expect(output[:stdout]).to include('DUPLICATES')
    end
  end

  describe 'probe subcommand' do
    let(:healthy_result) do
      {
        timestamp: '2026-07-25T00:00:00Z',
        domain: 'example.com',
        url: 'https://example.com',
        http: { status_code: 200, status_message: 'OK', success: true },
        ssl: {
          valid: true, subject: '/CN=example.com', issuer: '/CN=Test CA',
          not_before: '2026-01-01T00:00:00Z', not_after: '2027-01-01T00:00:00Z',
          days_until_expiry: 180, expired: false, not_yet_valid: false
        },
        health: 'healthy'
      }
    end

    def stub_probe(result)
      probe = double('Probe', call: result)
      allow(Onetime::Operations::Domains::Probe).to receive(:new).and_return(probe)
      probe
    end

    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'probe')
      expect(output[:stderr]).to include('was called with no arguments')
    end

    it 'exits 1 when the domain cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('notfound.com').and_return(nil)

      output = run_cli_command_quietly('domains', 'probe', 'notfound.com')
      expect(output[:stdout]).to include('Domain not found: notfound.com')
      expect(last_exit_code).to eq(1)
    end

    it 'emits a JSON error and exits 1 when the domain cannot be resolved with --json' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('notfound.com').and_return(nil)

      output = run_cli_command_quietly('domains', 'probe', 'notfound.com', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('notfound.com')
      expect(last_exit_code).to eq(1)
    end

    it 'reports a healthy domain' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      stub_probe(healthy_result)

      output = run_cli_command_quietly('domains', 'probe', 'example.com')
      expect(output[:stdout]).to include('HEALTHY')
      expect(last_exit_code).to eq(0)
    end

    it 'emits the op result hash verbatim with --json (parity contract)' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      stub_probe(healthy_result)

      output  = run_cli_command_quietly('domains', 'probe', 'example.com', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to contain_exactly('timestamp', 'domain', 'url', 'http', 'ssl', 'health')
      expect(payload['health']).to eq('healthy')
    end

    it 'exits 0 when the domain is unhealthy (health is an answer, not a failure)' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      stub_probe(
        timestamp: '2026-07-25T00:00:00Z',
        domain: 'example.com',
        url: 'https://example.com',
        http: { error: 'DNS Resolution Failed', message: 'getaddrinfo' },
        health: 'dns_error'
      )

      output = run_cli_command_quietly('domains', 'probe', 'example.com')
      expect(output[:stdout]).to include('DNS resolution failed')
      expect(last_exit_code).to eq(0)
    end

    it 'resolves the domain by extid' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('cd123abc').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('cd123abc').and_return(domain)
      stub_probe(healthy_result)

      output = run_cli_command_quietly('domains', 'probe', 'cd123abc')
      expect(output[:stdout]).to include('HEALTHY')
      expect(last_exit_code).to eq(0)
    end

    # dry-cli does not coerce `type: :integer`; the command must, or a String
    # timeout reaches Net::HTTP and raises inside IO.select.
    it 'passes --timeout to the op as an Integer and does not clamp it' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      probe = double('Probe', call: healthy_result)
      expect(Onetime::Operations::Domains::Probe).to receive(:new)
        .with(hostname: 'example.com', timeout: 120, insecure: false)
        .and_return(probe)

      run_cli_command_quietly('domains', 'probe', 'example.com', '--timeout', '120')
      expect(last_exit_code).to eq(0)
    end

    it 'rejects a non-numeric --timeout' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      expect(Onetime::Operations::Domains::Probe).not_to receive(:new)

      output = run_cli_command_quietly('domains', 'probe', 'example.com', '--timeout', 'soon')
      expect(output[:stdout]).to include('--timeout must be an integer')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'repair subcommand' do
    let(:orphan) do
      double('OrphanDomain',
        domainid: 'orphan.com',
        display_domain: 'orphan.com',
        org_id: '',
        extid: 'cdorphan',
        updated: Time.now.to_i,
        save: true,
        'updated=': nil,
        'org_id=': nil
      )
    end

    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'repair')
      expect(output[:stderr]).to include('was called with no arguments')
    end

    it 'detects and repairs domain issues with --yes' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])  # Domain not in collection
      allow(organization).to receive(:add_domain)
      allow(domain).to receive(:save)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--yes')
      expect(output[:stdout]).to include('Repair complete')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when the domain cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).with('notfound.com').and_return(nil)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('notfound.com').and_return(nil)

      output = run_cli_command_quietly('domains', 'repair', 'notfound.com', '--yes')
      expect(output[:stdout]).to include('Domain not found: notfound.com')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 when an orphaned domain is repaired without --org-id' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(orphan)

      output = run_cli_command_quietly('domains', 'repair', 'orphan.com', '--yes')
      expect(output[:stdout]).to include('orphaned')
      expect(last_exit_code).to eq(1)
    end

    it 'resolves --org-id by extid when Organization.load misses' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(orphan)
      allow(Onetime::Organization).to receive(:find_by_extid).with('on123abc').and_return(organization)
      allow(Onetime::Organization).to receive(:load).and_return(nil)
      allow(organization).to receive(:add_domain)

      output = run_cli_command_quietly('domains', 'repair', 'orphan.com', '--org-id', 'on123abc', '--yes')
      expect(output[:stdout]).to include('Repair complete')
      expect(output[:stdout]).to include('Assigned to organization org123')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 before prompting when --org-id cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(orphan)
      allow(Onetime::Organization).to receive(:find_by_extid).with('nope').and_return(nil)
      allow(Onetime::Organization).to receive(:load).and_return(nil)

      output = run_cli_command_quietly('domains', 'repair', 'orphan.com', '--org-id', 'nope')
      expect(output[:stdout]).to include('Organization not found: nope')
      expect(output[:stdout]).not_to include('Apply')
      expect(last_exit_code).to eq(1)
    end

    it 'refuses --org-id against a domain that already has an org and points at transfer' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:find_by_extid).with('on999xyz').and_return(organization)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--org-id', 'on999xyz', '--yes')
      expect(output[:stdout]).to include('domains transfer example.com --to-org')
      expect(last_exit_code).to eq(1)
    end

    it '--dry-run prints the plan and mutates nothing' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--dry-run')
      expect(output[:stdout]).to include('Dry run')
      expect(organization).not_to have_received(:add_domain)
      expect(last_exit_code).to eq(0)
    end

    it '--dry-run wins over --yes' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--dry-run', '--yes')
      expect(output[:stdout]).to include('Dry run')
      expect(organization).not_to have_received(:add_domain)
      expect(last_exit_code).to eq(0)
    end

    it '--json --yes emits the Result shape' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)
      allow(domain).to receive(:save)

      output  = run_cli_command_quietly('domains', 'repair', 'example.com', '--yes', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to contain_exactly(
        'status', 'domain_id', 'extid', 'display_domain', 'issues', 'repairs_applied', 'dry_run'
      )
      expect(payload['status']).to eq('repaired')
      expect(payload['dry_run']).to be(false)
      expect(last_exit_code).to eq(0)
    end

    it '--json without --yes or --dry-run refuses and exits 1' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--json')
      expect(JSON.parse(output[:stdout])['error']).to include('--yes')
      expect(last_exit_code).to eq(1)
    end

    it 'aborts without mutating when the operator declines the prompt' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('domains', 'repair', 'example.com')
      expect(output[:stdout]).to include('Aborted.')
      expect(organization).not_to have_received(:add_domain)
      expect(last_exit_code).to eq(0)
    end

    it 'treats EOF on stdin as a declined prompt instead of raising' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)
      allow($stdin).to receive(:gets).and_return(nil)

      output = run_cli_command_quietly('domains', 'repair', 'example.com')
      expect(output[:stdout]).to include('Aborted.')
      expect(organization).not_to have_received(:add_domain)
      expect(last_exit_code).to eq(0)
    end
  end

  # `bulk-repair` is retired. Its deprecation-shim coverage lives with its
  # replacement, in spec/cli/domains_doctor_command_spec.rb.

  describe 'orphaned subcommand' do
    it 'lists domains without organization' do
      orphaned_domain = double('Domain',
        domainid: 'orphaned.com',
        domain_name: 'orphaned.com',
        display_domain: 'orphaned.com',
        org_id: '',
        verified: 'true',
        verification_state: 'verified',
        created: Time.now.to_i
      )
      allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([orphaned_domain.domainid])
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(orphaned_domain)

      output = run_cli_command_quietly('domains', 'orphaned')
      expect(output[:stdout]).to include('orphaned custom domains')
    end
  end
end
