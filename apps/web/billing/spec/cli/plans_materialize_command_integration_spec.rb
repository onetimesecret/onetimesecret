# apps/web/billing/spec/cli/plans_materialize_command_integration_spec.rb
#
# frozen_string_literal: true

# Integration spec for `bin/ots billing plans materialize --include-memberships`.
# Exercises the cascade end-to-end: real Redis, real Familia models, real plan
# catalog loaded from spec/billing.test.yaml. The doubles-based unit specs in
# spec/operations/materialize_plans_spec.rb prove the accounting invariants;
# this spec proves the cascade actually writes to the membership documents.
#
# Run: pnpm run test:rspec apps/web/billing/spec/cli/plans_materialize_command_integration_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/plans_materialize_command'
# Loaded so the spec passes in isolation: the with_test_plans context calls
# mock_region!, which references Billing::Controllers::Base. Required after
# billing_spec_helper (which runs OT.boot!) so base.rb's includes resolve.
require_relative '../../controllers/base'

RSpec.describe 'Billing Plans Materialize CLI (integration)', :integration do
  include_context 'with_test_plans'

  subject(:command) { Onetime::CLI::BillingPlansMaterializeCommand.new }

  before { allow(command).to receive(:boot_application!) }

  def run_command(**kwargs)
    old_stdout = $stdout
    $stdout    = StringIO.new
    command.call(**kwargs)
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  # Real Customer + Organization. Billing is enabled in these specs, so
  # Organization.create! does NOT materialize the org (standalone
  # materialization is a no-op in billing mode) — that's what the command is
  # supposed to do. The owner membership IS materialized at create time, so a
  # freshly created org already has one active (owner) membership.
  def create_org(display_name:, email_seed:, planid: 'identity_plus_v1')
    email    = "plans-materialize-#{email_seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org      = Onetime::Organization.create!(display_name, customer, email)
    org.planid = planid
    org.save
    [org, customer]
  end

  # Real OrganizationMembership via add_members_instance — the same path the
  # operation's active_for_org lookup will find.
  def add_member(org:, role:, email_seed:)
    email    = "plans-materialize-mem-#{email_seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org.add_members_instance(
      customer,
      through_attrs: {
        role:      role,
        status:    'active',
        joined_at: Familia.now.to_f,
      },
    )
  end

  describe '--include-memberships --run' do
    it 'writes membership entitlements as (org.entitlements ∩ ROLE_ENTITLEMENTS[role])' do
      org, _owner = create_org(display_name: 'Cascade Co', email_seed: 'cascade')
      admin       = add_member(org: org, role: 'admin',  email_seed: 'admin')
      member      = add_member(org: org, role: 'member', email_seed: 'plain')

      expect(admin.entitlements_materialized?).to be false
      expect(member.entitlements_materialized?).to be false

      output = run_command(all: true, include_memberships: true, run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).to match(/Orgs cascaded:\s+1/)

      org.refresh!
      admin.refresh!
      member.refresh!

      expect(org.entitlements_materialized?).to be true
      expect(admin.entitlements_materialized?).to be true
      expect(member.entitlements_materialized?).to be true

      # Role intersection: custom_domains is on the plan AND in the admin
      # template but NOT the member template — admin must have it, member
      # must not. This single contrast proves the intersection ran; broad
      # plan-only entitlements (create_secrets, api_access) prove nothing
      # about role filtering since both roles are entitled to them.
      admin_ents  = admin.materialized_entitlements.to_a
      member_ents = member.materialized_entitlements.to_a
      expect(admin_ents).to      include('custom_domains')
      expect(member_ents).not_to include('custom_domains')

      # Owner-only entitlement granted by the plan must not leak down. This
      # proves the template is a ceiling, not a floor.
      expect(admin_ents).not_to include('custom_mail_sender')
    end

    it 'does not touch membership entitlements when --include-memberships is omitted' do
      org, _ = create_org(display_name: 'No Cascade Co', email_seed: 'no-cascade')
      admin  = add_member(org: org, role: 'admin', email_seed: 'no-cascade-admin')

      output = run_command(all: true, run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).not_to include('Orgs cascaded:')

      org.refresh!
      admin.refresh!
      expect(org.entitlements_materialized?).to be true
      expect(admin.entitlements_materialized?).to be false
    end

    it 'counts the org as FAILED when any membership materialization raises' do
      org, _   = create_org(display_name: 'Partial Cascade Co', email_seed: 'partial')
      ok_mem   = add_member(org: org, role: 'member', email_seed: 'ok')
      bad_mem  = add_member(org: org, role: 'admin',  email_seed: 'bad')

      # Force one membership to raise during cascade. Stubs the loaded
      # instances coming out of OrganizationMembership.active_for_org (which
      # routes through load_multi). Coupled to the active_for_org loader
      # contract — see organization_membership.rb#active_for_org. If that
      # method ever changes its batch primitive, this fault injection needs
      # to follow.
      allow(Onetime::OrganizationMembership).to receive(:load_multi)
        .and_wrap_original do |orig, *args|
          loaded = orig.call(*args)
          loaded.each do |m|
            next unless m && m.objid == bad_mem.objid

            allow(m).to receive(:materialize_for_role!).and_raise(StandardError, 'simulated boom')
          end
          loaded
        end

      output = run_command(all: true, include_memberships: true, run: true)

      expect(output).to match(/Failed:\s+1/)
      expect(output).to match(/Memberships failed:\s+1/)
      expect(output).to include('membership failures')

      org.refresh!
      ok_mem.refresh!
      # Org-level write happened before the cascade; the failure is purely
      # in the cascade. The good membership still got materialized — the
      # operation does not roll back partial cascade work. The org-level
      # FAILED count is the operator-visible signal.
      expect(org.entitlements_materialized?).to be true
      expect(ok_mem.entitlements_materialized?).to be true
    end
  end

  describe '--all dry-run (no writes)' do
    it 'previews without writing org or membership entitlements to Redis' do
      org, _ = create_org(display_name: 'Dry Run Co', email_seed: 'dry')
      member = add_member(org: org, role: 'admin', email_seed: 'dry-admin')

      expect(org.entitlements_materialized?).to be false
      expect(member.entitlements_materialized?).to be false

      # No --run flag → dry run. --include-memberships set to prove the cascade
      # is also skipped in preview mode.
      output = run_command(all: true, include_memberships: true)

      expect(output).to include('DRY RUN MODE')
      expect(output).to match(/Would materialize:.*identity_plus_v1/)

      org.refresh!
      member.refresh!
      expect(org.entitlements_materialized?).to be false
      expect(member.entitlements_materialized?).to be false
    end
  end

  describe '--plan filter' do
    it 'materializes only orgs on the named plan and leaves off-plan orgs untouched in Redis' do
      on_plan, _  = create_org(display_name: 'On Plan Co', email_seed: 'on-plan',
                               planid: 'identity_plus_v1')
      off_plan, _ = create_org(display_name: 'Off Plan Co', email_seed: 'off-plan',
                               planid: 'free_v1')

      output = run_command(plan: 'identity_plus_v1', run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).to match(/Skipped \(plan filter\):\s+1/)

      on_plan.refresh!
      off_plan.refresh!
      expect(on_plan.entitlements_materialized?).to be true
      expect(off_plan.entitlements_materialized?).to be false
    end
  end

  describe 'org with no plan' do
    it 'skips an org whose planid is empty and does not write its entitlements' do
      org, _ = create_org(display_name: 'No Plan Co', email_seed: 'no-plan-org', planid: '')

      output = run_command(all: true, run: true)

      expect(output).to match(/Skipped \(no plan\):\s+1/)
      expect(output).to match(/Succeeded:\s+0/)

      org.refresh!
      expect(org.entitlements_materialized?).to be false
    end
  end

  describe 'org on a plan missing from the catalog' do
    it "reports 'not found' for the bad org while other orgs in the batch still complete" do
      good, _ = create_org(display_name: 'Good Co', email_seed: 'good',
                           planid: 'identity_plus_v1')
      bad,  _ = create_org(display_name: 'Bad Co', email_seed: 'bad',
                           planid: 'nonexistent_plan_v1')

      output = run_command(all: true, run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).to match(/Failed:\s+1/)
      expect(output).to include("Plan 'nonexistent_plan_v1' not found")

      good.refresh!
      bad.refresh!
      expect(good.entitlements_materialized?).to be true
      expect(bad.entitlements_materialized?).to be false
    end
  end

  describe 'cascade with zero active memberships' do
    it 'cascades successfully (orgs_cascaded=1, memberships_succeeded=0)' do
      org, _ = create_org(display_name: 'Empty Co', email_seed: 'empty',
                          planid: 'identity_plus_v1')
      # Drop the auto-created owner membership from the active set so the org
      # has no active members to cascade to.
      org.members.clear
      expect(Onetime::OrganizationMembership.active_for_org(org)).to be_empty

      output = run_command(all: true, include_memberships: true, run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).to match(/Orgs cascaded:\s+1/)
      expect(output).to match(/Memberships materialized:\s+0/)
      # memberships_failed is 0, so the CLI omits that line entirely.
      expect(output).not_to match(/Memberships failed:/)

      org.refresh!
      expect(org.entitlements_materialized?).to be true
    end
  end

  describe 'cascade with mixed pending and active memberships' do
    it 'materializes active memberships and leaves pending invitations untouched' do
      org, owner_cust = create_org(display_name: 'Mixed Co', email_seed: 'mixed',
                                   planid: 'identity_plus_v1')
      active_member   = add_member(org: org, role: 'admin', email_seed: 'mixed-active')
      pending         = Onetime::OrganizationMembership.create_invitation!(
        organization: org,
        email:        'plans-materialize-mixed-pending@example.com',
        inviter:      owner_cust,
        role:         'member',
      )

      expect(active_member.entitlements_materialized?).to be false
      expect(pending.entitlements_materialized?).to be false

      output = run_command(all: true, include_memberships: true, run: true)

      expect(output).to match(/Succeeded:\s+1/)
      expect(output).to match(/Orgs cascaded:\s+1/)

      active_member.refresh!
      pending.refresh!
      # The active membership got materialized by the cascade...
      expect(active_member.entitlements_materialized?).to be true
      # ...but the pending invitation is not in org.members, so active_for_org
      # never sees it and it stays unmaterialized.
      expect(pending.entitlements_materialized?).to be false
    end
  end

  describe 'cascade with a role that has no entitlement template' do
    # Real materialize_for_role! failure — no stub. A membership whose role is
    # absent from ROLE_ENTITLEMENTS (e.g. a role removed from the catalog)
    # makes materialize_for_role! return false (it does not raise). The
    # operation treats that no-op as a cascade failure so the unmaterialized
    # membership isn't masked as a clean success.
    it 'counts the org as FAILED and leaves the bad-role membership unmaterialized' do
      org, _     = create_org(display_name: 'Bad Role Co', email_seed: 'bad-role',
                              planid: 'identity_plus_v1')
      bad_member = add_member(org: org, role: 'guest', email_seed: 'guest')

      expect(Onetime::OrganizationMembership::ROLE_ENTITLEMENTS).not_to have_key('guest')

      # --verbose surfaces the per-membership failure reason on the cascade line.
      output = run_command(all: true, include_memberships: true, run: true, verbose: true)

      expect(output).to match(/Failed:\s+1/)
      expect(output).to match(/Memberships failed:\s+1/)
      expect(output).to include('membership failures')
      expect(output).to include('role=guest')
      expect(output).to include("returned false for role 'guest'")

      org.refresh!
      bad_member.refresh!
      # The org-level write happens before the cascade, so the org is written.
      expect(org.entitlements_materialized?).to be true
      # The bad-role membership was never materialized (genuine no-op).
      expect(bad_member.entitlements_materialized?).to be false
    end
  end
end
