# spec/support/shared_contexts/default_workspace_lookup_context.rb
#
# frozen_string_literal: true

# Regression fixture for every lookup of "the customer's default workspace".
#
# Organization#is_default marks the organization its OWNER auto-created, so a
# member of someone else's default workspace sees the flag on it too. Three
# organizations, in the order a customer's memberships can list them:
#
#   1. foreign_default  — another owner's default workspace the customer
#                         joined (flagged, live, not owned)
#   2. archived_default — the customer's own former default workspace
#                         (flagged, owned, archived)
#   3. owned_default    — the customer's live owned default workspace
#
# A lookup that acts on the customer's own workspace (SSO self-heal, the
# federation claim, the pro-bono grant, checkout, the organization quota)
# must select owned_default whatever the order; one that stops at the first
# is_default flag selects foreign_default. The user-default lookup
# (OrganizationLoader.default_organization) follows an explicit
# default_org_id to foreign_default but never reaches it through the flag.
#
# Each spec builds its own customer double and passes it to
# stub_workspace_ownership so the owner? stubs match that double.
RSpec.shared_context 'default workspace lookup fixture' do
  let(:foreign_default) do
    instance_double(
      Onetime::Organization,
      objid: 'org-foreign-default',
      extid: 'or_foreign_default',
      display_name: "Someone else's Workspace",
      is_default: true,
      archived?: false,
      planid: 'team_plus_v1',
      stripe_customer_id: 'cus_foreign_default',
    )
  end

  let(:archived_default) do
    instance_double(
      Onetime::Organization,
      objid: 'org-archived-default',
      extid: 'or_archived_default',
      display_name: 'Archived Workspace',
      is_default: true,
      archived?: true,
      planid: 'identity_plus_v1',
      stripe_customer_id: 'cus_archived_default',
    )
  end

  let(:owned_default) do
    instance_double(
      Onetime::Organization,
      objid: 'org-owned-default',
      extid: 'or_owned_default',
      display_name: 'Default Workspace',
      is_default: true,
      archived?: false,
      planid: 'free_v1',
      stripe_customer_id: nil,
    )
  end

  # Membership order under test: the foreign default first.
  let(:lookup_fixture_orgs) { [foreign_default, archived_default, owned_default] }

  def stub_workspace_ownership(customer)
    allow(foreign_default).to receive(:owner?).with(customer).and_return(false)
    allow(archived_default).to receive(:owner?).with(customer).and_return(true)
    allow(owned_default).to receive(:owner?).with(customer).and_return(true)
  end
end
