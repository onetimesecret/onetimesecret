# apps/web/billing/spec/operations/materialize_plans_integration_spec.rb
#
# frozen_string_literal: true

# Operation-level integration spec for Billing::Operations::MaterializePlans.
# Real Redis, real Familia models, real plan catalog from spec/billing.test.yaml.
#
# The doubles-based spec (materialize_plans_spec.rb) proves the accounting
# invariants; the CLI integration spec (../cli/plans_materialize_command_integration_spec.rb)
# proves the cascade writes through the full command. This spec covers the
# operation's `membership_loader:` seam against real models — exercising a
# cascade failure without stubbing OrganizationMembership.active_for_org's
# internal batch primitive (load_multi). If active_for_org ever swaps that
# primitive, this test keeps working because it injects at the loader boundary,
# not at an implementation detail.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/materialize_plans_integration_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../operations/materialize_plans'
# Loaded so the spec passes in isolation: the with_test_plans context calls
# mock_region!, which references Billing::Controllers::Base. Required after
# billing_spec_helper (which runs OT.boot!) so base.rb's includes resolve.
require_relative '../../controllers/base'

RSpec.describe Billing::Operations::MaterializePlans, :integration do
  include_context 'with_test_plans'

  # Real Customer + Organization, unmaterialized at the org level (billing is
  # enabled, so create! does not materialize the org). The owner membership IS
  # materialized at create time.
  def create_org(email_seed:, planid: 'identity_plus_v1')
    email    = "mp-op-#{email_seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org      = Onetime::Organization.create!("Op #{email_seed}", customer, email)
    org.planid = planid
    org.save
    [org, customer]
  end

  def add_member(org:, role:, email_seed:)
    email    = "mp-op-mem-#{email_seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org.add_members_instance(
      customer,
      through_attrs: { role: role, status: 'active', joined_at: Familia.now.to_f },
    )
  end

  describe 'membership_loader seam (real Redis)' do
    it 'injects a cascade failure through the loader without stubbing active_for_org internals' do
      org, _ = create_org(email_seed: 'seam')
      good   = add_member(org: org, role: 'member', email_seed: 'good')

      expect(good.entitlements_materialized?).to be false

      # The seam returns the REAL active memberships (owner + the added
      # member), then forces just the 'member' one to raise. This is the
      # decoupled replacement for wrapping active_for_org's internal
      # load_multi: it injects at the stable loader boundary instead.
      loader = lambda do |o|
        members = Onetime::OrganizationMembership.active_for_org(o)
        members.each do |m|
          next unless m.role == 'member'

          allow(m).to receive(:materialize_for_role!).and_raise(StandardError, 'seam boom')
        end
        members
      end

      result = described_class.call(include_memberships: true, membership_loader: loader)

      # Org is FAILED because the cascade had a failure; the owner membership
      # still materialized for real, so the partial success is visible.
      expect(result.succeeded).to eq(0)
      expect(result.failed).to eq(1)
      expect(result.orgs_cascaded).to eq(1)
      expect(result.memberships_succeeded).to eq(1)
      expect(result.memberships_failed).to eq(1)
      expect(result.errors.first[:reason]).to include('membership failures')

      # The org-level write is real and happened before the cascade ran.
      org.refresh!
      good.refresh!
      expect(org.entitlements_materialized?).to be true
      # The injected raise short-circuited the write, so the member is still
      # unmaterialized in Redis.
      expect(good.entitlements_materialized?).to be false
    end

    it 'defaults to active_for_org when no loader is injected (real cascade writes)' do
      org, _ = create_org(email_seed: 'default')
      member = add_member(org: org, role: 'admin', email_seed: 'default-admin')

      expect(member.entitlements_materialized?).to be false

      result = described_class.call(include_memberships: true)

      expect(result.succeeded).to eq(1)
      expect(result.orgs_cascaded).to eq(1)
      # owner (auto-created) + the added admin both materialize.
      expect(result.memberships_succeeded).to eq(2)
      expect(result.memberships_failed).to eq(0)

      member.refresh!
      expect(member.entitlements_materialized?).to be true
    end
  end
end
