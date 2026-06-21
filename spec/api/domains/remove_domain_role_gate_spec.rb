# spec/integration/api/domains/remove_domain_role_gate_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for #3340: RemoveDomain now requires the custom_domains
# entitlement (admin+), consistent with AddDomain (#3033) and GetDomain.
# Previously any org member could delete a domain.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec spec/integration/api/domains/remove_domain_role_gate_spec.rb
#
RSpec.describe 'RemoveDomain role gate (#3340)', type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    require 'domains/logic/base'
    require 'domains/logic/domains/remove_domain'
  end

  let(:run_id) { "rmgate_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  let!(:owner) do
    Onetime::Customer.create!(email: "#{run_id}_owner@test.com")
  end

  let!(:organization) do
    org = Onetime::Organization.create!("RM Gate Org #{run_id}", owner, "#{run_id}_org@test.com")
    org.materialize_standalone_entitlements! if org.respond_to?(:materialize_standalone_entitlements!)
    owner_m = Onetime::OrganizationMembership.find_by_org_customer(org.objid, owner.objid)
    owner_m&.materialize_for_role! if owner_m&.respond_to?(:materialize_for_role!)
    org
  end

  let!(:admin_user) do
    Onetime::Customer.create!(email: "#{run_id}_admin@test.com")
  end

  let!(:member_user) do
    Onetime::Customer.create!(email: "#{run_id}_member@test.com")
  end

  let!(:admin_membership) do
    membership = organization.add_members_instance(admin_user, through_attrs: { role: 'admin' })
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  let!(:member_membership) do
    membership = organization.add_members_instance(member_user, through_attrs: { role: 'member' })
    membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
    membership
  end

  after do
    organization.list_domains.each { |d| d.destroy! rescue nil }
    admin_membership&.destroy! rescue nil
    member_membership&.destroy! rescue nil
    organization&.destroy! rescue nil
    admin_user&.destroy! rescue nil
    member_user&.destroy! rescue nil
    owner&.destroy! rescue nil
  end

  def strategy_result_for(customer)
    double(
      'StrategyResult',
      session: {},
      user: customer,
      authenticated?: true,
      auth_method: 'sessionauth',
      metadata: { organization_context: { organization: organization } },
    )
  end

  def create_domain_for_removal(label)
    domain = Onetime::CustomDomain.new
    domain.display_domain = "#{run_id}-#{label}.example.com"
    domain.org_id = organization.objid
    domain.save
    organization.domains.add(domain.objid)
    domain
  end

  def build_remove_logic(customer, domain)
    DomainsAPI::Logic::Domains::RemoveDomain.new(
      strategy_result_for(customer),
      { 'extid' => domain.extid },
    )
  end

  describe 'owner role' do
    it 'can delete a domain' do
      domain = create_domain_for_removal('owner-rm')
      logic = build_remove_logic(owner, domain)
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'admin role' do
    it 'can delete a domain (has custom_domains entitlement)' do
      domain = create_domain_for_removal('admin-rm')
      logic = build_remove_logic(admin_user, domain)
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'member role' do
    it 'is rejected with EntitlementRequired (lacks custom_domains)' do
      domain = create_domain_for_removal('member-rm')
      logic = build_remove_logic(member_user, domain)
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired)
    end

    it 'tags the error with the entitlement-required i18n key' do
      domain = create_domain_for_removal('member-rm-key')
      logic = build_remove_logic(member_user, domain)
      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired) do |error|
        expect(error.error_key).to eq('api.entitlements.errors.custom_domains_required')
      end
    end
  end

  describe 'non-member' do
    let!(:outsider) do
      Onetime::Customer.create!(email: "#{run_id}_outsider@test.com")
    end

    after do
      outsider&.destroy! rescue nil
    end

    it 'gets "Domain not found" before reaching the entitlement gate' do
      domain = create_domain_for_removal('outsider-rm')
      logic = build_remove_logic(outsider, domain)
      expect { logic.raise_concerns }.to raise_error(OT::FormError, /Domain not found/)
    end
  end

  describe 'domain-scope enforcement' do
    let!(:scoped_admin) do
      Onetime::Customer.create!(email: "#{run_id}_scoped@test.com")
    end

    let!(:domain_a) { create_domain_for_removal('scope-a') }

    let!(:scoped_membership) do
      membership = organization.add_members_instance(
        scoped_admin,
        through_attrs: {
          role: 'admin',
          status: 'active',
          domain_scope_id: domain_a.objid,
        },
      )
      membership.materialize_for_role! if membership.respond_to?(:materialize_for_role!)
      membership
    end

    after do
      scoped_membership&.destroy! rescue nil
      scoped_admin&.destroy! rescue nil
    end

    it 'domain-scoped admin is denied deletion of out-of-scope domain' do
      other_domain = create_domain_for_removal('scope-other')
      logic = build_remove_logic(scoped_admin, other_domain)
      expect { logic.raise_concerns }.to raise_error(OT::RecordNotFound, 'Domain not found')
    end

    it 'domain-scoped admin can delete their scoped domain' do
      logic = build_remove_logic(scoped_admin, domain_a)
      expect { logic.raise_concerns }.not_to raise_error
    end
  end
end
