# spec/unit/onetime/logic/colonel/investigate_organization_audit_spec.rb
#
# frozen_string_literal: true

# InvestigateOrganization's audit contract (#4336).
#
# POST /organizations/:org_id/investigate pulls a named customer's LIVE Stripe
# subscription state. It was one of two colonel routes that left no trace of
# who looked. These tests pin the success event, its detail shape (what was
# compared — never the Stripe material itself), and the AuditedFailure half.
#
# Message expectations, not store reads: ColonelAuditEvent.record swallows its
# own errors and returns nil, so a store read could pass or fail for reasons
# unrelated to the mechanism (the failure_audit_spec.rb convention).
#
# Run: pnpm run test:rspec spec/unit/onetime/logic/colonel/investigate_organization_audit_spec.rb

require 'spec_helper'
require 'colonel/application'

RSpec.describe ColonelAPI::Logic::Colonel::InvestigateOrganization do
  # verify_one_of_roles!(colonel: true) reads anonymous? / verified? / role, so
  # the double answers the real policy rather than stubbing the guard away.
  let(:colonel) do
    double(
      'Customer',
      extid: 'ur_colonel_public', role: 'colonel', objid: 'cust-obj-1',
      anonymous?: false, verified?: true,
    )
  end

  let(:org) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_public',
      planid: 'identity_plus_v1',
      stripe_customer_id: 'cus_live_secret',
      # Empty subscription id: fetch_stripe_state short-circuits without
      # touching the Stripe API, so these tests need no network double.
      stripe_subscription_id: '',
      subscription_status: 'active',
      subscription_period_end: nil,
    )
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      metadata: { ip: '127.0.0.1' },
      auth_method: 'sessionauth',
    )
  end

  def build(org_id: 'on_org_public')
    described_class.new(strategy_result, { 'org_id' => org_id })
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_public').and_return(org)
  end

  it 'records ONE result: :success event naming the org, not the operator' do
    logic = build
    logic.process_params
    logic.raise_concerns
    logic.process

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_colonel_public',
      verb: described_class::AUDIT_VERB,
      target: 'on_org_public',
      result: :success,
      detail: {
        verdict: 'unable_to_compare',
        stripe_available: false,
        issue_count: 0,
      },
    )
  end

  it 'is not fail-closed: an investigation destroys nothing' do
    logic = build
    logic.process_params
    logic.raise_concerns
    logic.process

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_excluding(:fail_closed),
    )
  end

  it 'records the divergence COUNT, never the Stripe identifiers compared' do
    allow(Billing::BillingService).to receive(:compare_billing_states).and_return(
      match: false,
      verdict: 'mismatch_detected',
      issues: [
        { field: 'planid', local: 'free_v1', stripe: 'identity_plus_v1', severity: 'high' },
        { field: 'stripe_subscription_id', local: nil, stripe: 'sub_live_secret', severity: 'critical' },
      ],
    )

    logic = build
    logic.process_params
    logic.raise_concerns
    logic.process

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(detail: { verdict: 'mismatch_detected', stripe_available: false, issue_count: 2 }),
    )
    # The response body may carry Stripe ids; the audit detail must not.
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(
      hash_including(detail: hash_including(:stripe_customer_id)),
    )
  end

  # The AuditedFailure half. #process is wrapped, #raise_concerns is not — so a
  # comparison that blows up records, and the colonel-role rejection cannot.
  it 'records ONE result: :failure event when the investigation raises, and re-raises' do
    allow(Billing::BillingService).to receive(:compare_billing_states)
      .and_raise(StandardError, 'stripe catalog unreachable')

    logic = build
    logic.process_params
    logic.raise_concerns

    expect { logic.process }.to raise_error(StandardError, /stripe catalog unreachable/)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_colonel_public',
      verb: described_class::AUDIT_VERB,
      target: 'on_org_public',
      result: :failure,
      detail: { error: 'StandardError', message: 'stripe catalog unreachable' },
    )
  end

  it 'records NOTHING for a non-colonel: the rejection is outside the audited region' do
    staff = double(
      'Customer',
      extid: 'ur_staff_public', role: 'staff', objid: 'cust-obj-2',
      anonymous?: false, verified?: true,
    )
    logic = described_class.new(
      double(
        'StrategyResult',
        session: {}, user: staff, metadata: { ip: '127.0.0.1' }, auth_method: 'sessionauth',
      ),
      { 'org_id' => 'on_org_public' },
    )
    logic.process_params

    expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end
end
