# spec/cli/org_create_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org create` (#3731).
#
# Pure adapter coverage: owner resolution, the dry-run default (nothing
# written without --apply, no prompt), and the op-status -> exit-code mapping. The mutation and
# the audit event are the op's job and are covered (against a real datastore) by
# spec/unit/onetime/operations/org/create_spec.rb, so here the op is stubbed at
# its constructor.
#
# This lives in its own file rather than appended to spec/cli/org_command_spec.rb
# because that file is owned by a concurrent lane.
#
# Run: tests/lanes/run unit --only spec/cli/org_create_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/create_command'

RSpec.describe 'Org Create Command', type: :cli do
  let(:owner) do
    double(
      'Customer',
      extid: 'ur_owner_ext',
      objid: 'cust-obj-1',
      custid: 'cust-obj-1',
      anonymous?: false,
      obscure_email: 'o****r@example.com',
    )
  end

  let(:result) do
    Onetime::Operations::Org::Create::Result.new(
      status: :created,
      org_id: 'on_new_ext',
      objid: 'org-obj-1',
      display_name: 'Acme',
      owner_id: 'ur_owner_ext',
      contact_email: 'billing@acme.test',
      message: nil,
    )
  end

  let(:operation) { instance_double(Onetime::Operations::Org::Create, call: result) }

  before do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email)
      .with('owner@example.com').and_return(owner)
    allow(Onetime::Operations::Org::Create).to receive(:new).and_return(operation)
  end

  describe 'argument + owner resolution' do
    it 'requires a DISPLAY_NAME argument' do
      run_cli_command_quietly('org', 'create')

      expect(last_exit_code).to eq(1)
      expect(Onetime::Operations::Org::Create).not_to have_received(:new)
    end

    # dry-cli does not enforce `required:` on options, so the command must.
    it 'exits 1 when --owner is omitted entirely' do
      output = run_cli_command_quietly('org', 'create', 'Acme', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: --owner is required')
      expect(Onetime::Operations::Org::Create).not_to have_received(:new)
    end

    it 'exits 1 when the owner cannot be resolved' do
      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'nope@example.com', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Customer not found: nope@example.com')
      expect(Onetime::Operations::Org::Create).not_to have_received(:new)
    end

    it 'refuses an anonymous owner (ADR-023: never fabricate one)' do
      allow(owner).to receive(:anonymous?).and_return(true)

      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('anonymous customer')
      expect(Onetime::Operations::Org::Create).not_to have_received(:new)
    end

  end

  describe 'dry run (the default)' do
    let(:result) do
      Onetime::Operations::Org::Create::Result.new(
        status: :planned,
        org_id: nil,
        objid: nil,
        display_name: 'Acme',
        owner_id: 'ur_owner_ext',
        contact_email: 'billing@acme.test',
        message: nil,
      )
    end

    it 'asks the op for a dry run without --apply, never prompting' do
      allow($stdin).to receive(:gets)

      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com')

      expect(last_exit_code).to eq(0)
      expect(Onetime::Operations::Org::Create).to have_received(:new).with(
        display_name: 'Acme',
        owner: owner,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        contact_email: nil,
        description: nil,
        dry_run: true,
      )
      expect(output[:stdout]).to include('DRY RUN — nothing was written')
      expect(output[:stdout]).to include("Would create 'Acme' owner=o****r@example.com")
      expect(output[:stdout]).to include('Re-run with --apply to create.')
      expect($stdin).not_to have_received(:gets)
    end

    it 'emits dry_run: true in --json and exits 0' do
      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])).to include('status' => 'planned', 'dry_run' => true)
    end

    it 'refuses --apply with --dry-run before calling the op' do
      output = run_cli_command_quietly(
        'org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply', '--dry-run'
      )

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--apply and --dry-run are contradictory')
      expect(Onetime::Operations::Org::Create).not_to have_received(:new)
    end
  end

  describe 'with --apply' do
    it 'asks the op to write' do
      run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply')

      expect(Onetime::Operations::Org::Create).to have_received(:new).with(hash_including(dry_run: false))
    end

    it 'treats --yes as --apply' do
      run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--yes')

      expect(Onetime::Operations::Org::Create).to have_received(:new).with(hash_including(dry_run: false))
    end
  end

  describe 'op invocation' do
    it 'attributes the audit actor to the shared CLI sentinel, never a Customer' do
      run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply')

      expect(Onetime::Operations::Org::Create).to have_received(:new)
        .with(hash_including(actor: 'cli'))
    end

    it 'passes the optional contact_email and description through verbatim' do
      run_cli_command_quietly(
        'org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply',
        '--contact-email', 'billing@acme.test', '--description', 'Primary tenant'
      )

      expect(Onetime::Operations::Org::Create).to have_received(:new).with(
        hash_including(contact_email: 'billing@acme.test', description: 'Primary tenant')
      )
    end

    it 'never audits from the adapter' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)

      run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply')

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'output' do
    it 'prints the new extid on the text path and exits 0' do
      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include("on_new_ext created: 'Acme' owner=o****r@example.com")
      expect(output[:stdout]).to include('objid: org-obj-1')
    end

    it 'emits the flat Result payload and exits 0 on --json --apply' do
      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply', '--json')

      payload = JSON.parse(output[:stdout])
      expect(last_exit_code).to eq(0)
      expect(payload['status']).to eq('created')
      expect(payload['org_id']).to eq('on_new_ext')
      expect(payload['objid']).to eq('org-obj-1')
      expect(payload['owner_id']).to eq('ur_owner_ext')
      expect(payload['owner_email']).to eq('o****r@example.com')
    end

    it 'exits 1 and prints the rejection message on the text path' do
      allow(operation).to receive(:call).and_return(
        result.with(
          status: :email_taken,
          org_id: nil,
          objid: nil,
          message: 'Organization exists for that email address',
        )
      )

      output = run_cli_command_quietly(
        'org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply',
        '--contact-email', 'billing@acme.test'
      )

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization exists for that email address')
    end

    it 'exits 1 with the rejection payload on the json path' do
      allow(operation).to receive(:call).and_return(
        result.with(status: :name_too_long, org_id: nil, objid: nil, message: 'Display name must be 100 characters or fewer')
      )

      output = run_cli_command_quietly('org', 'create', 'Acme', '--owner', 'owner@example.com', '--apply', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['status']).to eq('name_too_long')
    end
  end
end
