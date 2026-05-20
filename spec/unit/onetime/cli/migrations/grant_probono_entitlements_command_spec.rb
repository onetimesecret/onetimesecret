# spec/unit/onetime/cli/migrations/grant_probono_entitlements_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for GrantProbonoEntitlementsCommand — the CLI wrapper.
#
# Business logic lives in Billing::Operations::GrantProbonoEntitlements
# and is covered by apps/web/billing/spec/operations/grant_probono_entitlements_spec.rb.
#
# This spec covers the CLI's responsibilities:
# - update_stats: maps each Result#status to the right counter
# - report_result: formats verbose output per status
# - process_customer: delegates to the operation, aggregates, rescues errors
#
# Run: pnpm run test:rspec spec/unit/onetime/cli/migrations/grant_probono_entitlements_command_spec.rb

require 'spec_helper'
require 'onetime/cli'
require 'billing/operations/grant_probono_entitlements'

RSpec.describe Onetime::CLI::GrantProbonoEntitlementsCommand do
  subject(:command) { described_class.new }

  let(:result_class) { Billing::Operations::GrantProbonoResult }

  let(:customer) do
    double('Customer', extid: 'cust_ext_1', email: 'p@example.com')
  end

  let(:stats) do
    {
      total: 0,
      granted: 0,
      skipped_no_org: 0,
      skipped_already_complimentary: 0,
      errors: [],
    }
  end

  before do
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
    allow(OT).to receive(:le)
  end

  # ---------------------------------------------------------------------------
  # update_stats
  # ---------------------------------------------------------------------------

  describe '#update_stats (private)' do
    {
      granted:                       :granted,
      would_grant:                   :granted,
      skipped_no_org:                :skipped_no_org,
      skipped_already_complimentary: :skipped_already_complimentary,
    }.each do |status, counter|
      it "increments stats[:#{counter}] when status is :#{status}" do
        result = result_class.new(
          status: status, customer_extid: 'c', org_extid: 'o', reason: nil,
        )

        command.send(:update_stats, stats, result)

        expect(stats[counter]).to eq(1)
      end
    end

    it 'does not increment errors for non-error statuses' do
      result = result_class.new(
        status: :granted, customer_extid: 'c', org_extid: 'o', reason: nil,
      )
      command.send(:update_stats, stats, result)
      expect(stats[:errors]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # report_result
  # ---------------------------------------------------------------------------

  describe '#report_result (private)' do
    let(:result_granted) do
      result_class.new(
        status: :granted, customer_extid: 'cust_ext_1', org_extid: 'org_ext_1', reason: nil,
      )
    end

    let(:result_would_grant) do
      result_class.new(
        status: :would_grant, customer_extid: 'cust_ext_1', org_extid: 'org_ext_1', reason: nil,
      )
    end

    let(:result_no_org) do
      result_class.new(
        status: :skipped_no_org, customer_extid: 'cust_ext_1', org_extid: nil,
        reason: 'Customer has no organization',
      )
    end

    let(:result_already) do
      result_class.new(
        status: :skipped_already_complimentary, customer_extid: 'cust_ext_1',
        org_extid: 'org_ext_1', reason: nil,
      )
    end

    it 'prints nothing when verbose is false' do
      expect(command).not_to receive(:puts)

      command.send(:report_result, result_granted, '[1/1]', false)
    end

    it 'prints "Would grant" line for :would_grant' do
      expect(command).to receive(:puts).with(/\[1\/1\] Would grant: cust_ext_1.*org_ext_1/)

      command.send(:report_result, result_would_grant, '[1/1]', true)
    end

    it 'prints "Granted" line for :granted' do
      expect(command).to receive(:puts).with(/\[1\/1\] Granted: cust_ext_1.*org_ext_1/)

      command.send(:report_result, result_granted, '[1/1]', true)
    end

    it 'prints "no organization" line for :skipped_no_org' do
      expect(command).to receive(:puts).with(/\[1\/1\] Skipping cust_ext_1 \(no organization\)/)

      command.send(:report_result, result_no_org, '[1/1]', true)
    end

    it 'prints "already complimentary" line for :skipped_already_complimentary' do
      expect(command).to receive(:puts).with(/\[1\/1\] Skipping cust_ext_1 \(org already complimentary\)/)

      command.send(:report_result, result_already, '[1/1]', true)
    end
  end

  # ---------------------------------------------------------------------------
  # process_customer (orchestration)
  # ---------------------------------------------------------------------------

  describe '#process_customer (private)' do
    let(:granted_result) do
      result_class.new(
        status: :granted, customer_extid: 'cust_ext_1', org_extid: 'org_ext_1', reason: nil,
      )
    end

    it 'delegates to GrantProbonoEntitlements.call with dry_run and force' do
      expect(Billing::Operations::GrantProbonoEntitlements)
        .to receive(:call)
        .with(customer, dry_run: true, force: false)
        .and_return(granted_result)

      command.send(:process_customer, customer, 0, 1, stats, true, false, false)

      expect(stats[:total]).to eq(1)
      expect(stats[:granted]).to eq(1)
    end

    it 'passes force: true through to the operation' do
      expect(Billing::Operations::GrantProbonoEntitlements)
        .to receive(:call)
        .with(customer, dry_run: false, force: true)
        .and_return(granted_result)

      command.send(:process_customer, customer, 0, 1, stats, false, false, true)
    end

    it 'increments errors and continues when the operation raises' do
      allow(Billing::Operations::GrantProbonoEntitlements)
        .to receive(:call)
        .and_raise(StandardError.new('boom'))

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include('cust_ext_1')
      expect(stats[:errors].first).to include('boom')
    end

    it 'logs Stripe-style "plan missing" errors via OT.le' do
      allow(Billing::Operations::GrantProbonoEntitlements)
        .to receive(:call)
        .and_raise(Billing::PlanCacheMissError.new('plan missing', plan_id: 'identity'))

      expect(OT).to receive(:le).with(/cust_ext_1.*plan missing/)

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)
    end
  end
end
