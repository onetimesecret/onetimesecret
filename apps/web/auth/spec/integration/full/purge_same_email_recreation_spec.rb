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

  def purge(customer, deep: false)
    Auth::Operations::Customers::Purge.new(
      customer: customer,
      actor: actor,
      reason: 'issue #4440 integration regression',
      deep: deep,
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

    recreated, recreated_account, = create_and_verify(normalized_email)
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

  [false, true].each do |deep|
    %i[legacy_email blank].each do |creator|
      it "purges completed migration and canceled billing history with #{creator} creator (deep: #{deep})" do
        email = unique_test_email('purge-migrated')
        customer, account, workspace, membership = create_and_verify(email)
        customer.v1_custid = email
        customer.migration_status = 'completed'
        customer.migrated_at = (Time.now.to_i - 3600).to_s
        customer.save

        expect(customer.custid).to eq(customer.objid)
        expect(customer.custid).not_to eq(email)

        timestamp = Time.now.to_i - 3600
        billing_claims = {
          stripe_customer_id: "cus_purge_#{SecureRandom.hex(8)}",
          stripe_subscription_id: "sub_purge_#{SecureRandom.hex(8)}",
          billing_email: email,
          stripe_checkout_email: email,
        }
        billing_claims.each { |field, value| workspace.public_send("#{field}=", value) }
        workspace.created_by = creator == :legacy_email ? email : ''
        workspace.subscription_status = 'canceled'
        workspace.planid = 'identity_plus_v1'
        workspace.subscription_period_end = timestamp
        workspace.subscription_federated_at = timestamp
        workspace.federation_notification_dismissed_at = timestamp
        workspace.email_hash = SecureRandom.hex(32)
        workspace.email_hash_synced_at = Time.at(timestamp).utc.strftime('%Y-%m-%d@%H:%MZ')
        workspace.migration_status = 'completed'
        workspace.migrated_at = timestamp.to_s
        workspace.migration_comment = 'created_synthesized'
        workspace.v1_source_custid = email
        # The organization generator records the v2 customer key, not its legacy email key.
        workspace.v1_identifier = customer.dbkey
        workspace.save

        other_owner = Onetime::Customer.create!(email: unique_test_email('hash-owner'), verified: true)
        other_org = Onetime::Organization.create!(
          "Unrelated hash holder #{SecureRandom.hex(4)}", other_owner, other_owner.email,
        )
        other_org.email_hash = workspace.email_hash
        other_org.save
        other_membership = Onetime::OrganizationMembership.find_by_org_customer(other_org.objid, other_owner.objid)

        customer_id = customer.objid
        workspace_id = workspace.objid
        membership_id = membership.objid
        hash_index = Onetime::Organization.email_hash_index_for(workspace.email_hash)
        billing_indexes = billing_claims.map do |field, value|
          [Onetime::Organization.public_send("#{field}_index"), value]
        end

        expect(workspace.billing_live?).to be(false)
        expect(Onetime::Organization.contact_email_index.get(email)).to eq(workspace_id)
        billing_indexes.each { |index, value| expect(index.get(value)).to eq(workspace_id) }
        # Inspect raw members: a finder could hide a dangling reference to a deleted org.
        expect(hash_index.membersraw).to contain_exactly(workspace_id, other_org.objid)
        expect(other_membership).to be_active
        expect(auth_db[:account_password_hashes].where(id: account[:id]).count).to eq(1)

        result = purge(Onetime::Customer.load(customer_id), deep: deep)

        expect(result.status).to eq(:success), result.blockers.inspect
        expect(result.actions.map { |action| action[:type] }).to contain_exactly(:delete_organization)
        expect(Onetime::Customer.load(customer_id)).to be_nil
        expect(Onetime::Customer.find_by_email(email)).to be_nil
        expect(Onetime::Organization.load(workspace_id)).to be_nil
        expect(Onetime::Organization.instances.to_a.map(&:to_s)).not_to include(workspace_id)
        expect(Onetime::OrganizationMembership.load(membership_id)).to be_nil
        expect(Onetime::OrganizationMembership.find_by_org_customer(workspace_id, customer_id)).to be_nil
        expect(customer.participations.to_a).to be_empty
        expect(customer.organization_instances.to_a).to be_empty
        expect(Onetime::Organization.contact_email_index.get(email)).to be_nil
        billing_indexes.each { |index, value| expect(index.get(value)).to be_nil }
        expect(hash_index.membersraw).to contain_exactly(other_org.objid)
        expect(Onetime::Organization.load(other_org.objid)).not_to be_nil
        expect(Onetime::Organization.contact_email_index.get(other_owner.email)).to eq(other_org.objid)
        expect(Onetime::OrganizationMembership.load(other_membership.objid)).to be_active
        expect(other_org.member?(other_owner)).to be(true)
        expect(other_owner.organization_instances.to_a.map(&:objid)).to contain_exactly(other_org.objid)
        expect(auth_db[:accounts].where(id: account[:id]).first).to include(
          external_id: customer.extid,
          status_id: AuthTestConstants::STATUS_CLOSED,
        )
        expect(auth_db[:account_password_hashes].where(id: account[:id]).count).to eq(0)

        # Exercise local index release and reuse, not the signup flow.
        recreated = Onetime::Customer.create!(email: email, verified: true)
        recreated_workspace = Onetime::Organization.create!(
          "Recreated purge workspace #{SecureRandom.hex(4)}", recreated, email, is_default: true,
        )
        expect(recreated.objid).not_to eq(customer_id)
        expect(Onetime::Customer.find_by_email(email).objid).to eq(recreated.objid)
        expect_valid_default_workspace(recreated)
        expect(recreated_workspace.objid).not_to eq(workspace_id)
        # Released billing claims must be reusable, not merely absent from model lookup.
        billing_claims.each { |field, value| recreated_workspace.public_send("#{field}=", value) }
        recreated_workspace.save
        billing_indexes.each { |index, value| expect(index.get(value)).to eq(recreated_workspace.objid) }
        expect(hash_index.membersraw).to contain_exactly(other_org.objid)
      end
    end
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
