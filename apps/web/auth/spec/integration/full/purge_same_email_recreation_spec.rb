# apps/web/auth/spec/integration/full/purge_same_email_recreation_spec.rb
#
# frozen_string_literal: true

# Full-stack regression coverage for issue #4440. These examples intentionally
# cross the Rodauth/PostgreSQL and Familia/Valkey boundary with real records:
# signup -> verification -> organization policy -> administrative purge ->
# same-email recreation -> login -> entitlement-gated API request.
#
# Run:
#   tests/lanes/run full-pg --only \
#     apps/web/auth/spec/integration/full/purge_same_email_recreation_spec.rb

require_relative '../../spec_helper'

RSpec.describe 'Customer purge and same-email recreation (#4440)',
               type: :integration,
               postgres_database: true do
  before(:all) do
    boot_onetime_app
    require 'auth/operations/customers/purge'
    require 'auth/operations/set_customer_verification'
  end

  let(:password) { AuthTestConstants::TEST_PASSWORD }
  let(:actor) { 'ur_issue_4440_operator' }

  def create_and_verify(login)
    Auth::Config.create_account(login: login, password: password)

    email    = OT::Utils.normalize_email(login)
    customer = Onetime::Customer.find_by_email(email)
    raise "signup did not create Customer for #{email}" unless customer

    result = Auth::Operations::SetCustomerVerification.new(
      customer: customer,
      verified: true,
      verified_by: 'email',
    ).call
    raise "verification failed for #{email}: #{result.inspect}" unless %i[success no_change].include?(result)

    account = auth_db[:accounts]
      .where(external_id: customer.extid, status_id: AuthTestConstants::STATUS_VERIFIED)
      .first
    raise "verification did not leave an open Rodauth identity for #{email}" unless account

    workspace = customer.organization_instances.to_a.find { |org| org.is_default.to_s == 'true' }
    raise "signup did not create a default workspace for #{email}" unless workspace

    membership = Onetime::OrganizationMembership.find_by_org_customer(workspace.objid, customer.objid)
    raise "default workspace has no active owner membership for #{email}" unless membership&.active? && membership.owner?

    [customer, account, workspace, membership]
  end

  def purge(customer)
    Auth::Operations::Customers::Purge.new(
      customer: customer,
      actor: actor,
      reason: 'issue #4440 integration regression',
    ).call
  end

  def build_shared_membership(customer)
    owner = Onetime::Customer.create!(email: unique_test_email('shared-owner'), verified: true)
    org   = Onetime::Organization.create!(
      "Shared purge fixture #{SecureRandom.hex(4)}",
      owner,
      owner.email,
    )
    membership = Onetime::OrganizationMembership.ensure_membership(
      org,
      customer,
      role: 'member',
      provisioning_source: 'invited',
    )
    [owner, org, membership]
  end

  def attach_custom_domain(org)
    display = "purge-#{SecureRandom.hex(6)}.integration-test.example.com"
    domain  = Onetime::CustomDomain.new(display_domain: display, org_id: org.objid)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(display, domain.domainid)
    org.add_domain(domain)
    domain
  end

  def expect_valid_default_workspace(customer)
    orgs      = customer.organization_instances.to_a
    workspace = orgs.find { |org| org.is_default.to_s == 'true' }

    expect(workspace).to be_a(Onetime::Organization)
    expect(workspace.owner_id).to eq(customer.objid)
    expect(workspace.created_by).to eq(customer.objid)
    expect(workspace.member?(customer)).to be(true)
    expect(orgs.map(&:objid)).to include(workspace.objid)
    expect(Onetime::Organization.contact_email_index.get(customer.email)).to eq(workspace.objid)

    membership = Onetime::OrganizationMembership.find_by_org_customer(workspace.objid, customer.objid)
    expect(membership).not_to be_nil
    expect(membership).to be_active
    expect(membership).to be_owner
    expect(membership.can?('api_access')).to be(true)

    [workspace, membership]
  end

  it 'fully purges eligible references, removes a non-owner membership, and permits a working same-email account' do
    normalized_email = unique_test_email('purge-recreate')
    original_login   = "  #{normalized_email.upcase}  "
    original, original_account, original_workspace, original_membership = create_and_verify(original_login)
    shared_owner, shared_org, shared_membership = build_shared_membership(original)

    original_objid       = original.objid
    original_extid       = original.extid
    workspace_objid      = original_workspace.objid
    owner_membership_id  = original_membership.objid
    shared_membership_id = shared_membership.objid

    expect(original.email).to eq(normalized_email)
    expect(shared_org.member?(original)).to be(true)
    expect(original.organization_instances.to_a.map(&:objid))
      .to contain_exactly(workspace_objid, shared_org.objid)

    result = purge(original)

    expect(result.status).to eq(:success), result.blockers.inspect
    expect(result.actions.map { |action| action[:type] })
      .to contain_exactly(:delete_organization, :remove_membership)
    expect(Onetime::Customer.load(original_objid)).to be_nil
    expect(Onetime::Organization.load(workspace_objid)).to be_nil
    expect(Onetime::Organization.instances.to_a.map(&:to_s)).not_to include(workspace_objid)
    expect(Onetime::Organization.contact_email_index.get(normalized_email)).to be_nil
    expect(Onetime::OrganizationMembership.load(owner_membership_id)).to be_nil
    expect(Onetime::OrganizationMembership.load(shared_membership_id)).to be_nil
    expect(shared_org.member?(original_objid)).to be(false)
    expect(shared_owner.organization_instances.to_a.map(&:objid)).to include(shared_org.objid)
    expect(original.participations.to_a).to be_empty

    closed = auth_db[:accounts].where(id: original_account[:id]).first
    expect(closed[:external_id]).to eq(original_extid)
    expect(closed[:status_id]).to eq(AuthTestConstants::STATUS_CLOSED)

    recreated, recreated_account, = create_and_verify("\t#{normalized_email}\n")
    expect(recreated.objid).not_to eq(original_objid)
    expect(recreated_account[:id]).not_to eq(original_account[:id])

    clear_cookies
    csrf_login(normalized_email, password: password)
    expect(last_request.env.dig('rack.session', 'account_id')).to eq(recreated_account[:id])

    workspace, membership = expect_valid_default_workspace(recreated)

    api_token = recreated.regenerate_apitoken
    clear_body_headers
    header 'Accept', 'application/json'
    authorize normalized_email, api_token

    expect { get '/api/v2/receipt/recent' }.not_to raise_error
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include('success' => true, 'count' => 0)

    expect(Onetime::Organization.load(workspace.objid)).not_to be_nil
    expect(Onetime::OrganizationMembership.load(membership.objid)).not_to be_nil
  end

  it 'refuses before mutation when the owned default workspace retains a custom domain' do
    email = unique_test_email('purge-refused')
    customer, account, workspace, membership = create_and_verify(email)
    domain = attach_custom_domain(workspace)

    customer_objid  = customer.objid
    workspace_objid = workspace.objid
    membership_id   = membership.objid

    expect(workspace.domain_count).to eq(1)
    expect(domain.primary_organization&.objid).to eq(workspace_objid)

    result = purge(customer)

    expect(result.status).to eq(:refused)
    expect(result.stage).to eq(:preflight)
    expect(result.blockers.map { |blocker| blocker[:code] }).to include(:has_domains)

    preserved_customer = Onetime::Customer.load(customer_objid)
    preserved_account  = auth_db[:accounts].where(id: account[:id]).first
    preserved_org      = Onetime::Organization.load(workspace_objid)

    expect(preserved_customer).not_to be_nil
    expect(preserved_customer.extid).to eq(customer.extid)
    expect(preserved_account).to include(
      external_id: customer.extid,
      status_id: AuthTestConstants::STATUS_VERIFIED,
    )
    expect(auth_db[:account_password_hashes].where(id: account[:id]).count).to eq(1)
    expect(preserved_org).not_to be_nil
    expect(Onetime::Organization.instances.to_a.map(&:to_s)).to include(workspace_objid)
    expect(Onetime::Organization.contact_email_index.get(email)).to eq(workspace_objid)
    expect(Onetime::OrganizationMembership.load(membership_id)).not_to be_nil
    expect(preserved_org.member?(preserved_customer)).to be(true)
    expect(preserved_customer.organization_instances.to_a.map(&:objid)).to include(workspace_objid)
    expect(Onetime::CustomDomain.load(domain.objid)&.org_id).to eq(workspace_objid)
  end
end
