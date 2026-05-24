# spec/integration/api/domains/add_domain_role_gate_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for PR #3033 §2: only org owners and admins may add a
# custom domain. Mirrors the try-side coverage at
# try/integration/api/domains/add_domain_role_gate_try.rb, exercising the
# gate by driving the Logic class directly with real Customer / Organization /
# OrganizationMembership instances rather than through the Otto router.
#
# The HTTP-layer integration (sessionauth → 403 / 201) lives in the try test;
# this spec is the supplementary RSpec mirror called out by v3 §9.
RSpec.describe 'AddDomain role gate (#3033)', type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    require 'apps/api/domains/logic/base'
    require 'apps/api/domains/logic/domains/add_domain'
  end

  let(:run_id) { "addgate_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  let!(:owner) do
    Onetime::Customer.create!(email: "#{run_id}_owner@test.com")
  end

  let!(:organization) do
    Onetime::Organization.create!("Role Gate Org #{run_id}", owner, "#{run_id}_org@test.com")
  end

  let!(:admin_user) do
    Onetime::Customer.create!(email: "#{run_id}_admin@test.com")
  end

  let!(:member_user) do
    Onetime::Customer.create!(email: "#{run_id}_member@test.com")
  end

  let!(:admin_membership) do
    organization.add_members_instance(admin_user, through_attrs: { role: 'admin' })
  end

  let!(:member_membership) do
    organization.add_members_instance(member_user, through_attrs: { role: 'member' })
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

  # Build a StrategyResult double wired to the given customer + the org under
  # test. Matches the metadata shape that OrganizationContext consumes via
  # extract_organization_context.
  def strategy_result_for(customer)
    double(
      'StrategyResult',
      session:        {},
      user:           customer,
      authenticated?: true,
      auth_method:    'sessionauth',
      metadata:       { organization_context: { organization: organization } },
    )
  end

  def build_add_domain_logic(customer, domain:, org_id: nil)
    params = { 'domain' => domain }
    params['org_id'] = org_id if org_id
    DomainsAPI::Logic::Domains::AddDomain.new(strategy_result_for(customer), params)
  end

  describe 'owner role' do
    it 'passes the admin gate' do
      logic = build_add_domain_logic(owner, domain: "#{run_id}-owner.example.com")
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'admin role' do
    it 'passes the admin gate' do
      logic = build_add_domain_logic(admin_user, domain: "#{run_id}-admin.example.com")
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  describe 'member role' do
    it 'rejects with Onetime::Forbidden (not FormError)' do
      logic = build_add_domain_logic(member_user, domain: "#{run_id}-member.example.com")
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'rejection message references the admin requirement' do
      logic = build_add_domain_logic(member_user, domain: "#{run_id}-member-msg.example.com")
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden, /admin/i)
    end

    it 'does not create a domain when the gate rejects' do
      attempted = "#{run_id}-member-nocreate.example.com"
      logic = build_add_domain_logic(member_user, domain: attempted)
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(organization.list_domains.map(&:display_domain)).not_to include(attempted)
    end
  end

  describe 'member with explicit org_id' do
    let!(:secondary_org) do
      Onetime::Organization.create!("Secondary Org #{run_id}", owner, "#{run_id}_secondary@test.com")
    end

    let!(:secondary_member_membership) do
      secondary_org.add_members_instance(member_user, through_attrs: { role: 'member' })
    end

    after do
      secondary_org.list_domains.each { |d| d.destroy! rescue nil }
      secondary_member_membership&.destroy! rescue nil
      secondary_org&.destroy! rescue nil
    end

    it 'rejects with Onetime::Forbidden — gate runs against target_organization' do
      logic = build_add_domain_logic(
        member_user,
        domain: "#{run_id}-member-explicit.example.com",
        org_id: secondary_org.objid,
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'non-member with explicit org_id (regression: resolution check still runs first)' do
    let!(:foreign_org) do
      Onetime::Organization.create!("Foreign Org #{run_id}", owner, "#{run_id}_foreign@test.com")
    end

    after do
      foreign_org&.destroy! rescue nil
    end

    it 'rejects with FormError before reaching the admin gate' do
      # member_user has no membership in foreign_org, so resolve_target_organization
      # returns nil and raise_form_error('Organization not found or access denied')
      # fires before verify_organization_admin can run.
      logic = build_add_domain_logic(
        member_user,
        domain: "#{run_id}-foreign.example.com",
        org_id: foreign_org.objid,
      )
      expect { logic.raise_concerns }.to raise_error(
        Onetime::FormError,
        /access denied|not found/i,
      )
    end
  end
end
