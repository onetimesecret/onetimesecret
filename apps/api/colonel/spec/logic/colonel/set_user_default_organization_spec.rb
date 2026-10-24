# apps/api/colonel/spec/logic/colonel/set_user_default_organization_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/users/:user_id/default-organization — TIER 2 (#4326).
#
# This adapter owns HTTP concerns only: identifier resolution, the
# confirmation gate, the op-status -> 422 mapping and the response shape.
# Onetime::Operations::Customers::SetDefaultOrganization owns the membership /
# archived rule, the write and the ColonelAuditEvent (CONTRACT 4); its spec is
# spec/unit/onetime/operations/customers/set_default_organization_spec.rb. Here
# the op is stubbed at its constructor.
RSpec.describe ColonelAPI::Logic::Colonel::SetUserDefaultOrganization do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target', email: 'target@example.com',
      exists?: true, anonymous?: false)
  end

  let(:team) do
    instance_double(Onetime::Organization,
      objid: 'org_team_obj', extid: 'on_team', display_name: 'Team Org', exists?: true)
  end

  let(:home) do
    instance_double(Onetime::Organization,
      objid: 'org_home_obj', extid: 'on_home', display_name: 'Home Org', exists?: true)
  end

  let(:op_class) { Onetime::Operations::Customers::SetDefaultOrganization }

  def op_result(status, previous: home)
    op_class::Result.new(status: status, customer: target, organization: team, previous: previous, dry_run: false)
  end

  def stub_op(status, previous: home)
    allow(op_class).to receive(:new)
      .and_return(instance_double(op_class, call: op_result(status, previous: previous)))
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token = 'target@example.com')
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = 'target@example.com', params = {})
    described_class.new(
      strategy_result_for(user, confirm_token),
      { 'user_id' => 'ur_target', 'organization_id' => 'on_team' }.merge(params),
    )
  end

  def run(logic)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_target').and_return(target)
    allow(Onetime::Customer).to receive(:load).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_team').and_return(team)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    stub_op(:success)
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { 'target@example.com' }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'does not accept the extid the URL already carried' do
      expect { logic_for(colonel, 'ur_target').raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'calls no op when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(op_class).not_to have_received(:new)
    end
  end

  describe 'guards before the gate' do
    it 'refuses a non-colonel' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'requires an organization id' do
      expect { logic_for(colonel, nil, 'organization_id' => '') }
        .to raise_error(Onetime::FormError, /Organization is required/)
    end

    it 'answers 404 for an unknown user' do
      expect { logic_for(colonel, nil, 'user_id' => 'ur_ghost').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /User not found/)
    end

    it 'answers 404 for an unknown organization' do
      expect { logic_for(colonel, nil, 'organization_id' => 'on_ghost').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Organization not found/)
    end

    it 'resolves an organization objid when no extid matches' do
      allow(Onetime::Organization).to receive(:load).with('org_team_obj').and_return(team)

      run(logic_for(colonel, 'target@example.com', 'organization_id' => 'org_team_obj'))

      expect(op_class).to have_received(:new).with(hash_including(organization: team))
    end

    it 'refuses an anonymous user with a 422' do
      allow(target).to receive(:anonymous?).and_return(true)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::FormError, /anonymous/)
    end
  end

  describe 'the op call' do
    it 'passes the acting colonel extid and the sanitized reason' do
      run(logic_for(colonel, 'target@example.com', 'reason' => '  <b>ticket</b> 42 '))

      expect(op_class).to have_received(:new).with(
        customer: target, organization: team, actor: 'ur_colonel', reason: 'ticket 42',
      )
    end
  end

  describe 'the response' do
    it 'answers the contract shape on success' do
      expect(run(logic_for)).to eq(
        record: {
          extid: 'ur_target',
          default_organization: { extid: 'on_team', display_name: 'Team Org' },
        },
        details: {
          previous_default_organization: { extid: 'on_home', display_name: 'Home Org' },
        },
      )
    end

    it 'answers null for a customer who had no default' do
      stub_op(:success, previous: nil)

      expect(run(logic_for)[:details]).to eq(previous_default_organization: nil)
    end

    it 'answers 200 with the same shape when the organization was already the default' do
      stub_op(:no_change, previous: team)

      data = run(logic_for)

      expect(data[:record][:default_organization]).to eq(extid: 'on_team', display_name: 'Team Org')
      expect(data[:details][:previous_default_organization]).to eq(extid: 'on_team', display_name: 'Team Org')
    end
  end

  describe 'op refusals' do
    it 'maps :not_member to a 422 on organization_id' do
      stub_op(:not_member, previous: nil)

      expect { run(logic_for) }.to raise_error(Onetime::FormError, /not an active member/) { |ex|
        expect(ex.field).to eq(:organization_id)
      }
    end

    it 'maps :archived to a 422 on organization_id' do
      stub_op(:archived, previous: nil)

      expect { run(logic_for) }.to raise_error(Onetime::FormError, /archived/)
    end

    it 'fails loudly on a status it does not know' do
      stub_op(:something_new, previous: nil)

      expect { run(logic_for) }.to raise_error(Onetime::FormError, /did not complete \(something_new\)/)
    end

    # CONTRACT 4: the op owns the event, refusals included.
    it 'writes no audit event of its own' do
      stub_op(:not_member, previous: nil)

      expect { run(logic_for) }.to raise_error(Onetime::FormError)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
