# apps/web/auth/spec/operations/customers/doctor_closure_marker_spec.rb
#
# frozen_string_literal: true

# Unit tests for the closure-marker check in
# Auth::Operations::Customers::Doctor (#4830).
#
# A record that still carries Customer#closure_started_at is either a
# closure that stopped before the record was deleted (no open auth account:
# reported, finished by `customers finish-closures`, never here) or one that
# rolled back (open auth account: --repair clears the marker). A marker too
# young to tell those from a closure still running is left alone, and so is
# a record whose auth account could not be read.
#
# Follows doctor_sso_verified_spec.rb: the check is private and is exercised
# directly.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/doctor_closure_marker_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:issues)   { [] }
  let(:repaired) { [] }

  let(:now)            { 1_800_000_000 }
  let(:started_at)     { now - Onetime::Customer::CLOSURE_STALE_AFTER - 1 }
  let(:account_row)    { { id: 42, email: 'closing@example.com', status_id: Auth::AccountStatuses::VERIFIED } }
  let(:by_external_id) { double('by_external_id') }
  let(:db)             { double('db') }

  # A real Customer (never saved) for the predicates; only the marker clear
  # is stubbed, because it writes.
  let(:customer) do
    Onetime::Customer.new(email: 'closing@example.com').tap do |record|
      record.closure_started_at = started_at
      allow(record).to receive(:clear_closure_marker!)
    end
  end

  before do
    allow(OT).to receive(:info)
    allow(Familia).to receive(:now).and_return(now)
    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(db).to receive(:[]).with(:accounts).and_return(by_external_id)
    allow(by_external_id).to receive(:where).with(external_id: customer.extid).and_return(by_external_id)
    allow(by_external_id).to receive(:select).with(:id, :email, :status_id).and_return(by_external_id)
    allow(by_external_id).to receive(:first) { account_row }
  end

  def check(repair: false)
    described_class.new(customer: customer, repair: repair).send(:check_closure_marker, issues, repaired)
  end

  def checks
    issues.map { |issue| issue[:check] }
  end

  it 'reports nothing for a record no closure has touched' do
    customer.closure_started_at = nil

    check(repair: true)

    expect(issues).to be_empty
    expect(repaired).to be_empty
  end

  context 'when the auth account is gone' do
    let(:account_row) { nil }

    it 'reports an interrupted closure and points at finish-closures without repairing it' do
      check(repair: true)

      expect(checks).to eq([:closure_interrupted])
      expect(issues.first).to include(severity: :high, repairable: false)
      expect(issues.first[:message])
        .to include("bin/ots customers purge #{customer.extid}").and include('finish-closures')
      expect(customer).not_to have_received(:clear_closure_marker!)
    end
  end

  context 'when the auth account is closed' do
    let(:account_row) { { id: 42, email: 'closing@example.com', status_id: Auth::AccountStatuses::CLOSED } }

    it 'reports an interrupted closure' do
      check

      expect(checks).to eq([:closure_interrupted])
    end
  end

  context 'when the auth account is open' do
    it 'reports a rolled-back closure as repairable' do
      check

      expect(checks).to eq([:closure_rolled_back])
      expect(issues.first).to include(severity: :medium, repairable: true)
      expect(customer).not_to have_received(:clear_closure_marker!)
    end

    it 'clears the marker under --repair' do
      check(repair: true)

      expect(customer).to have_received(:clear_closure_marker!)
      expect(repaired).to eq([{ customer: customer.extid, action: :closure_marker_cleared }])
    end
  end

  # An uncommitted closure reads as an open account from here; clearing its
  # marker would let the closure commit without one.
  context 'when the marker is younger than a closure takes' do
    let(:started_at) { now - 60 }

    it 'reports the closure as in progress and leaves it alone' do
      check(repair: true)

      expect(checks).to eq([:closure_in_progress])
      expect(issues.first).to include(severity: :low, repairable: false)
      expect(customer).not_to have_received(:clear_closure_marker!)
    end
  end

  context 'when the auth database cannot be read' do
    before do
      allow(by_external_id).to receive(:first).and_raise(Sequel::DatabaseConnectionError, 'down')
    end

    it 'reports nothing rather than guess the state' do
      check(repair: true)

      expect(issues).to be_empty
      expect(customer).not_to have_received(:clear_closure_marker!)
    end
  end

  # The data checks run after this one. For a record that is still closing
  # they report but repair nothing: an unfinished closure is deleted by
  # finish-closures, not repaired into shape, and a blocked one still needs
  # the read-out.
  describe 'the data checks' do
    let(:runs) { [] }

    before do
      allow_any_instance_of(described_class).to receive(:check_customer_data) do |doctor, issues, _repaired|
        runs << doctor.send(:repairing?)
        issues << { check: :data_check, severity: :low, message: 'data', repairable: true }
      end
    end

    context 'when the closure was interrupted' do
      let(:account_row) { nil }

      it 'report without repairing, even under --repair, on the same doctor' do
        doctor = described_class.new(customer: customer, repair: true)
        allow(described_class).to receive(:new).and_call_original

        report = doctor.call

        expect(runs).to eq([false])
        expect(described_class).not_to have_received(:new)
        expect(report.issues.map { |issue| issue[:check] }).to include(:closure_interrupted, :data_check)
      end
    end

    context 'when the closure rolled back and --repair cleared the marker' do
      before do
        allow(customer).to receive(:clear_closure_marker!) { customer.closure_started_at = nil }
      end

      it 'run as usual' do
        described_class.new(customer: customer, repair: true).call

        expect(runs).to eq([true])
      end
    end
  end

  context 'in simple mode' do
    before { allow(Auth::Database).to receive(:connection).and_return(nil) }

    it 'reports an interrupted closure' do
      check

      expect(checks).to eq([:closure_interrupted])
    end
  end
end
