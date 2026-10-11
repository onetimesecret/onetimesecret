# apps/web/auth/spec/operations/customers/doctor_system_role_mailbox_spec.rb
#
# frozen_string_literal: true

# Unit tests for the :system_role_without_mailbox_proof check added to
# Auth::Operations::Customers::Doctor by #4735.
#
# has_system_role? refuses colonel/admin/staff to an account that is not
# Customer#mailbox_verified?, so a role holder whose only verification is an
# IdP stamp ('sso'), a card ('stripe_payment'), autoverify, a pre-provenance
# backfill ('legacy') or nothing at all holds a role that does nothing. The
# doctor reports it; it never repairs it, because only the operator can say the
# address belongs to the holder (`bin/ots customers verify` / colonel admin).
#
# Follows doctor_sso_verified_spec.rb: the check is private and is exercised
# directly, so a failure names this check rather than the other per-customer
# checks.
#
# Run: bundle exec rspec apps/web/auth/spec/operations/customers/doctor_system_role_mailbox_spec.rb

require 'spec_helper'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:issues) { [] }

  let(:role)        { 'colonel' }
  let(:verified)    { true }
  let(:verified_by) { 'sso' }

  let(:customer) do
    double(
      'Customer',
      email: 'ops@example.com',
      objid: 'obj_c',
      extid: 'ur_c',
      role: role,
      verified?: verified,
      verified_by: verified_by,
      mailbox_verified?: verified && Onetime::Customer::MAILBOX_VERIFIED_BY.include?(verified_by.to_s),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)
  end

  def run
    described_class.new(customer: customer, repair: false, actor: 'cli')
      .send(:check_system_role_mailbox_proof, issues)
  end

  def issue
    issues.find { |i| i[:check] == :system_role_without_mailbox_proof }
  end

  describe 'a colonel whose stamp is IdP-asserted' do
    it 'reports a high, non-repairable issue naming the provenance' do
      run

      expect(issue).not_to be_nil
      expect(issue[:severity]).to eq(:high)
      expect(issue[:repairable]).to be(false)
      expect(issue[:message]).to include("role 'colonel'").and include("verified_by: 'sso'")
      expect(issue[:repair_action]).to include('bin/ots customers verify')
    end
  end

  %w[stripe_payment autoverify legacy].each do |provenance|
    context "when verified_by is '#{provenance}'" do
      let(:verified_by) { provenance }

      it 'is reported — the stamp carries no mailbox proof' do
        run
        expect(issue).not_to be_nil
      end
    end
  end

  context 'when verified with no provenance at all' do
    let(:verified_by) { nil }

    it 'is reported, and says so' do
      run
      expect(issue[:message]).to include('verified with no provenance')
    end
  end

  context 'when the colonel is unverified' do
    let(:verified)    { false }
    let(:verified_by) { nil }

    it 'is reported as unverified' do
      run
      expect(issue[:message]).to include('(unverified)')
    end
  end

  %w[email invite_token cli_provision colonel_admin].each do |provenance|
    context "when verified_by is '#{provenance}'" do
      let(:verified_by) { provenance }

      it 'reports nothing — this is mailbox proof' do
        run
        expect(issue).to be_nil
      end
    end
  end

  # has_system_role? knows these roles, but the doctor's VALID_ROLES does not
  # (yet), so :role_invalid already reports such a record; this check stays
  # quiet rather than stacking a second issue on it.
  %w[admin staff].each do |system_role|
    context "when the role is '#{system_role}'" do
      let(:role) { system_role }

      it 'is left to the :role_invalid check' do
        run
        expect(issue).to be_nil
      end
    end
  end

  context 'when the customer holds no system role' do
    let(:role) { 'customer' }

    it 'reports nothing — ordinary accounts need no mailbox proof for anything the doctor tracks' do
      run
      expect(issue).to be_nil
    end
  end

  it 'is wired into the per-customer check list' do
    source = File.read(File.join(Onetime::HOME, 'apps/web/auth/operations/customers/doctor.rb'))
    expect(source).to include('check_system_role_mailbox_proof(issues)')
  end
end
