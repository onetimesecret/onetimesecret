# apps/api/account/spec/logic/account/update_organization_context_spec.rb
#
# frozen_string_literal: true

# Unit tests for organization (workspace) selection persistence in user
# sessions (#4565). The membership, archived and domain-scope decisions are
# made by the real Onetime::Application::OrganizationLoader; only the
# datastore reads are stubbed.
#
# Run with:
#   tests/lanes/run unit --only apps/api/account/spec/logic/account/update_organization_context_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateOrganizationContext do
  subject(:logic) do
    described_class.new(strategy_result, params)
  end

  let(:default_org) do
    instance_double(Onetime::Organization, objid: 'org-default-111', archived?: false)
  end

  let(:target_org) do
    instance_double(Onetime::Organization, objid: 'org-target-222', archived?: false)
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'test-cust-123',
      extid: 'urtest-cust-123',
      custid: 'test-cust-123',
      anonymous?: false,
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'organization_id' => nil,
    }
  end

  # The request's custom domains, as OrganizationLoader#load_organization_context
  # leaves them in the context. Empty on a canonical host.
  let(:scope_domains) { [] }

  let(:organization_context) do
    {
      organization: default_org,
      organization_id: default_org.objid,
      scope_domains: scope_domains,
    }
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: { organization_context: organization_context },
    )
  end

  let(:params) { { 'organization_id' => target_org.objid } }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:conf).and_return(
      {
        'site' => {},
        'features' => { 'domains' => { 'enabled' => true } },
      },
    )
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Organization).to receive(:load).with(target_org.objid).and_return(target_org)
    allow(Onetime::Organization).to receive(:load).with(default_org.objid).and_return(default_org)
    allow(target_org).to receive(:member?).with(customer).and_return(true)
    allow(default_org).to receive(:member?).with(customer).and_return(true)
  end

  describe '#process_params' do
    it 'extracts organization_id from params' do
      expect(logic.new_organization_id).to eq(target_org.objid)
    end

    it 'strips whitespace from the id' do
      params['organization_id'] = "  #{target_org.objid}  "
      logic                     = described_class.new(strategy_result, params)
      expect(logic.new_organization_id).to eq(target_org.objid)
    end

    it 'does not turn a malformed id into a different one' do
      params['organization_id'] = "../#{target_org.objid}"
      logic                     = described_class.new(strategy_result, params)
      expect(logic.new_organization_id).to be_nil
    end

    it 'rejects an overlong id' do
      params['organization_id'] = 'a' * (described_class::MAX_ORGANIZATION_ID_LENGTH + 1)
      logic                     = described_class.new(strategy_result, params)
      expect(logic.new_organization_id).to be_nil
    end

    it 'stores the old selection from session' do
      session['organization_id'] = default_org.objid
      logic                      = described_class.new(strategy_result, params)
      expect(logic.old_organization_id).to eq(default_org.objid)
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
        )
      end

      it 'raises FormError with unauthorized type' do
        expect { logic.raise_concerns }.to raise_error(OT::FormError, /Authentication required/)
      end
    end

    context 'when organization_id is missing' do
      let(:params) { { 'organization_id' => nil } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization is required/)
      end
    end

    context 'when organization_id is empty' do
      let(:params) { { 'organization_id' => '' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization is required/)
      end
    end

    context 'when the organization does not exist' do
      let(:params) { { 'organization_id' => 'org-unknown-999' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end
    end

    context 'when the customer is not a member' do
      before { allow(target_org).to receive(:member?).with(customer).and_return(false) }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end
    end

    context 'when the organization is archived' do
      before { allow(target_org).to receive(:archived?).and_return(true) }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end
    end

    context 'when the customer is a member of an active organization' do
      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    # The param is the objid, as in the O-Organization-ID header. An extid is
    # not looked up, so it resolves to nothing.
    context 'when given the extid rather than the objid' do
      let(:params) { { 'organization_id' => 'on_target_extid' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
        expect(Onetime::Organization).to have_received(:load).with('on_target_extid')
      end
    end

    context 'when the auth strategy supplied no organization context' do
      let(:strategy_result) do
        double('StrategyResult', session: session, user: customer, authenticated?: true, metadata: {})
      end

      it 'raises form error: the domain scope cannot be checked' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end
    end
  end

  # The membership's domain scope, on a request for a custom domain. The
  # predicate is the real OrganizationMembership#can_access_domain?.
  describe 'domain scope on a custom domain' do
    let(:request_domain) { double('request domain', objid: 'domain-request') }
    let(:other_domain)   { double('other domain', objid: 'domain-other') }
    let(:scope_domains)  { [request_domain] }
    let(:membership)     { Onetime::OrganizationMembership.new(domain_scope_id: scoped_to) }

    before do
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(target_org.objid, customer.objid).and_return(membership)
    end

    context 'when the membership is scoped to another domain' do
      let(:scoped_to) { other_domain.objid }

      it 'raises form error' do
        expect(membership.can_access_domain?(request_domain)).to be(false)
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end

      it 'does not update the session' do
        session['organization_id'] = default_org.objid
        logic                      = described_class.new(strategy_result, params)

        expect(logic.process).to be_nil
        expect(session['organization_id']).to eq(default_org.objid)
      end
    end

    context 'when the membership is scoped to the request domain' do
      let(:scoped_to) { request_domain.objid }

      it 'accepts the selection' do
        expect { logic.raise_concerns }.not_to raise_error
        logic.process
        expect(session['organization_id']).to eq(target_org.objid)
      end
    end

    context 'when the membership has no domain scope' do
      let(:scoped_to) { nil }

      it 'accepts the selection' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when there is no membership record' do
      let(:membership) { nil }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid organization/)
      end
    end
  end

  describe '#process' do
    context 'with a selectable organization' do
      it 'updates session with the organization objid' do
        logic.process
        expect(session['organization_id']).to eq(target_org.objid)
      end

      it 'stores the selection under a string key' do
        logic.process
        expect(session.keys).to all(be_a(String))
      end

      it 'returns success data with the new selection' do
        result = logic.process
        expect(result[:organization_id]).to eq(target_org.objid)
      end

      it 'returns the previous selection in response' do
        session['organization_id'] = default_org.objid
        new_logic                  = described_class.new(strategy_result, params)
        result                     = new_logic.process
        expect(result[:previous_organization_id]).to eq(default_org.objid)
      end

      it 'marks field as modified' do
        logic.process
        expect(logic.modified?(:organization_context)).to be true
      end

      it 'sets greenlighted to true' do
        logic.process
        expect(logic.greenlighted).to be true
      end

      # What the next request does with the value just written.
      it 'writes the value OrganizationLoader resolves on a request with no header' do
        logic.process

        loader = Class.new { include Onetime::Application::OrganizationLoader }.new
        allow(customer).to receive_messages(default_org_id: '', organization_instances: [default_org, target_org])
        context = loader.load_organization_context(customer, session, {})
        expect(context[:organization]).to eq(target_org)
      end
    end

    # Each refusal leaves the session exactly as it was, whether or not the
    # caller ran raise_concerns first.
    context 'when the selection is refused' do
      before { session['organization_id'] = default_org.objid }

      shared_examples 'a refused selection' do
        it 'returns nil without updating' do
          before_session = session.dup
          expect(logic.process).to be_nil
          expect(session).to eq(before_session)
        end

        it 'does not set greenlighted' do
          logic.process
          expect(logic.greenlighted).to be false
        end

        it 'leaves the session untouched when raise_concerns refuses' do
          before_session = session.dup
          expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
          expect(session).to eq(before_session)
        end
      end

      context 'with an organization the customer is not a member of' do
        before { allow(target_org).to receive(:member?).with(customer).and_return(false) }

        it_behaves_like 'a refused selection'
      end

      context 'with an archived organization' do
        before { allow(target_org).to receive(:archived?).and_return(true) }

        it_behaves_like 'a refused selection'
      end

      context 'with an unknown organization' do
        let(:params) { { 'organization_id' => 'org-unknown-999' } }

        it_behaves_like 'a refused selection'
      end

      context 'with a malformed id' do
        let(:params) { { 'organization_id' => 'org target/222' } }

        it_behaves_like 'a refused selection'
      end
    end

    # The time belongs to the selection and goes when the selection goes.
    context 'when the loader drops a selection that no longer holds' do
      before do
        logic.process
        allow(target_org).to receive(:archived?).and_return(true)
        allow(customer).to receive_messages(default_org_id: '', organization_instances: [default_org])
      end

      it 'drops its time with it' do
        loader = Class.new { include Onetime::Application::OrganizationLoader }.new
        loader.load_organization_context(customer, session, {})

        expect(session).not_to include('organization_id', 'organization_selected_at')
      end
    end

    # raise_concerns and perform_update each read the datastore. A change
    # landing between them makes the loader refuse the write; the response
    # must not then claim the selection was recorded.
    context 'when the membership is revoked between the checks' do
      before do
        session['organization_id'] = default_org.objid
        allow(target_org).to receive(:member?).with(customer).and_return(true, false)
        logic.raise_concerns
      end

      it 'refuses with the same error as the first check' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Invalid organization/)
      end

      it 'leaves the session as it was' do
        before_session = session.dup
        expect { logic.process }.to raise_error(Onetime::FormError)
        expect(session).to eq(before_session)
      end

      it 'does not mark the field as modified' do
        expect { logic.process }.to raise_error(Onetime::FormError)
        expect(logic.modified?(:organization_context)).to be false
      end

      it 'does not log the update' do
        app_log = instance_double(SemanticLogger::Logger, info: nil, debug: nil)
        allow(Onetime).to receive(:get_logger).and_call_original
        allow(Onetime).to receive(:get_logger).with('App').and_return(app_log)

        expect { logic.process }.to raise_error(Onetime::FormError)
        expect(app_log).not_to have_received(:info).with('Organization context updated', anything)
      end
    end
  end

  describe '#success_data' do
    it 'returns organization_id' do
      data = logic.success_data
      expect(data[:organization_id]).to eq(target_org.objid)
    end

    it 'returns previous_organization_id' do
      session['organization_id'] = default_org.objid
      new_logic                  = described_class.new(strategy_result, params)
      data                       = new_logic.success_data
      expect(data[:previous_organization_id]).to eq(default_org.objid)
    end
  end

  # The session write is only meaningful on a real session, so the route is
  # session-only like its domain-context sibling.
  describe 'route declaration' do
    let(:route_line) do
      File.readlines(File.join(Onetime::HOME, 'apps/api/account/routes.txt'))
        .find { |line| line.include?('/update-organization-context') }
    end

    it 'is a POST to this logic class with session auth only' do
      expect(route_line).to match(%r{\APOST\s+/update-organization-context\s+#{described_class.name}\s})
      expect(route_line).to include('response=json', 'auth=sessionauth')
      expect(route_line).not_to include('basicauth')
    end
  end
end
