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

  # Real Customer + Organization on identity_plus_v1. No materialization yet —
  # that's what the command is supposed to do.
  def create_org(display_name:, email_seed:)
    email    = "plans-materialize-#{email_seed}@example.com"
    customer = Onetime::Customer.create!(email: email)
    org      = Onetime::Organization.create!(display_name, customer, email)
    org.planid = 'identity_plus_v1'
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
end
