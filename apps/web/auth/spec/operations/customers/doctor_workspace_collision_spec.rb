# apps/web/auth/spec/operations/customers/doctor_workspace_collision_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/customers/doctor'
require 'auth/operations/create_default_workspace'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:customer) do
    double(
      'Customer',
      email: 'user@example.com',
      extid: 'ur_current',
      objid: 'cust_current',
      provisioning_failure_classification: 'retained_data',
    )
  end
  let(:classifier) { instance_double(Auth::Operations::WorkspaceCollision) }
  let(:provisioner) { instance_double(Auth::Operations::CreateDefaultWorkspace) }

  before do
    @provisioning_failed = true
    allow(customer).to receive(:provisioning_failed?) { @provisioning_failed }
    allow(Onetime::Customer).to receive(:load).with('cust_current').and_return(customer)
    allow(Auth::Operations::WorkspaceCollision).to receive(:new).and_return(classifier)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete).and_call_original
    allow(Auth::Operations::CreateDefaultWorkspace).to receive(:new)
      .with(customer: customer).and_return(provisioner)
    allow(provisioner).to receive(:call) { @provisioning_failed = false }
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(OT).to receive(:info)
  end

  def collision(classification, evidence: {}, raw: 'org_1')
    Auth::Operations::WorkspaceCollision::Result.new(
      classification: classification,
      email: 'user@example.com',
      organization: nil,
      raw_index_value: raw,
      evidence: { organization_extid: 'on_1' }.merge(evidence),
    )
  end

  def run_check(result, repair: false)
    allow(classifier).to receive(:call).and_return(result)
    issues   = []
    repaired = []
    op       = described_class.new(customer: customer, repair: repair, actor: 'cli')
    op.send(:check_workspace_collision, issues, repaired)
    [issues, repaired, op]
  end

  it 'reports a retained-data collision as manual and does not adopt it' do
    issues, repaired = run_check(collision(:retained_data), repair: true)

    expect(issues.first).to include(
      check: :workspace_collision_retained_data,
      classification: :retained_data,
      repairable: false,
    )
    expect(repaired).to be_empty
    expect(Auth::Operations::WorkspaceCollision).not_to have_received(:compare_and_delete)
  end

  it 'reports unreadable evidence as critical and unhealthy' do
    issues, = run_check(collision(:unreadable, evidence: { reason: 'NOAUTH' }))

    expect(issues.first).to include(
      check: :workspace_collision_unreadable,
      severity: :critical,
      repairable: false,
    )
  end

  it 'CAS-removes a phantom claim, provisions canonically, verifies it, and reports a completed repair' do
    stale = collision(:phantom_index)
    current = collision(
      :current_valid_workspace,
      evidence: { organization_extid: 'on_current' },
      raw: 'org_current',
    )
    allow(classifier).to receive(:call).and_return(stale, current)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete)
      .with(stale).and_return(true)

    issues   = []
    repaired = []
    op = described_class.new(customer: customer, repair: true, actor: 'cli')
    op.send(:check_workspace_collision, issues, repaired)
    op.send(:audit_repair_outcome, repaired)

    expect(provisioner).to have_received(:call).once
    expect(customer.provisioning_failed?).to be(false)
    expect(issues).to be_empty
    expect(repaired).to eq([
      {
        customer: 'ur_current',
        action: :workspace_collision_repaired,
        classification: :phantom_index,
        org: 'on_current',
      },
    ])
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        verb: 'customer.doctor_repair',
        result: :success,
        detail: { actions: [:workspace_collision_repaired] },
      ),
    )
  end

  it 'returns a failed partial repair and leaves the provisioning latch set when retry fails' do
    stale = collision(:index_mismatch)
    retry_collision = collision(:retained_data, raw: 'org_live')
    error = Auth::Operations::WorkspaceCollision::ProvisioningCollision.new(retry_collision)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete)
      .with(stale).and_return(true)
    allow(provisioner).to receive(:call).and_raise(error)

    issues, repaired, op = run_check(stale, repair: true)
    op.send(:audit_repair_outcome, repaired)

    expect(issues.map { |issue| issue[:check] }).to include(:workspace_provisioning_retry_failed)
    expect(issues.last).to include(repair_failed: true, partial: true, repairable: false)
    expect(repaired).to be_empty
    expect(customer.provisioning_failed?).to be(true)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        verb: 'customer.doctor_repair',
        result: :partial,
        detail: hash_including(
          actions: [:workspace_contact_email_index_removed],
          classification: :index_mismatch,
          retry_classification: :retained_data,
        ),
      ),
    )
  end

  it 'reports a partial failure when persisting the provisioning latch raises' do
    stale = collision(:phantom_index)
    retry_collision = collision(:retained_data, raw: 'org_live')
    retry_error = Auth::Operations::WorkspaceCollision::ProvisioningCollision.new(retry_collision)
    persistence_error = RuntimeError.new('save failed')
    persisted_customer = double('PersistedCustomer', provisioning_failed?: false)
    @provisioning_failed = false

    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete)
      .with(stale).and_return(true)
    allow(provisioner).to receive(:call).and_raise(retry_error)
    allow(customer).to receive(:mark_provisioning_failed!) do
      @provisioning_failed = true
      raise persistence_error
    end
    allow(Onetime::Customer).to receive(:load).with('cust_current').and_return(persisted_customer)

    issues, repaired, op = run_check(stale, repair: true)
    op.send(:audit_repair_outcome, repaired)

    expect(issues).to contain_exactly(hash_including(
      check: :workspace_provisioning_retry_failed,
      message: include('durable failure state could not be verified or updated'),
      repair_failed: true,
      partial: true,
    ))
    expect(repaired).to be_empty
    expect(persisted_customer.provisioning_failed?).to be(false)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        verb: 'customer.doctor_repair',
        result: :partial,
        detail: hash_including(latch_error: 'RuntimeError: save failed'),
      ),
    )
  end

  it 'reports a latched provisioning failure on every run even when the workspace is current' do
    current = collision(:current_valid_workspace, raw: 'org_current')
    allow(classifier).to receive(:call).and_return(current)

    reports = 2.times.map do
      issues = []
      op = described_class.new(customer: customer, repair: false, actor: 'cli')
      op.send(:check_workspace_collision, issues, [])
      op.send(:check_provisioning_failure, issues)
      issues
    end

    reports.each do |issues|
      expect(issues).to include(hash_including(
        check: :workspace_provisioning_failed,
        severity: :critical,
        classification: 'retained_data',
      ))
    end
    expect(Auth::Operations::CreateDefaultWorkspace).not_to have_received(:new)
  end

  it 'does not provision or clear unsafe collisions' do
    [:retained_data, :live_members, :unreadable].each do |classification|
      issues, repaired = run_check(collision(classification), repair: true)

      expect(issues.first[:classification]).to eq(classification)
      expect(repaired).to be_empty
    end

    expect(Auth::Operations::WorkspaceCollision).not_to have_received(:compare_and_delete)
    expect(Auth::Operations::CreateDefaultWorkspace).not_to have_received(:new)
    expect(customer.provisioning_failed?).to be(true)
  end

  it 'leaves a concurrently changed claim untouched' do
    result = collision(:index_mismatch)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete)
      .with(result).and_return(false)

    _issues, repaired = run_check(result, repair: true)

    expect(repaired).to be_empty
  end
end
