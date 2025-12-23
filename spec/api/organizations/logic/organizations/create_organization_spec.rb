# spec/api/organizations/logic/organizations/create_organization_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Organizations::CreateOrganization do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      organization_instances: organization_instances
    )
  end

  let(:organization_instances) { double('SortedSet', to_a: [], size: 0, first: nil) }
  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) do
    {
      'display_name' => 'My Organization',
      'description' => 'A test organization',
      'contact_email' => 'contact@example.com'
    }
  end

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
  end

  describe '#process_params' do
    it 'extracts display_name from params' do
      expect(logic.display_name).to eq('My Organization')
    end

    it 'extracts description from params' do
      expect(logic.description).to eq('A test organization')
    end

    it 'extracts contact_email from params' do
      expect(logic.contact_email).to eq('contact@example.com')
    end

    it 'strips whitespace from display_name' do
      params['display_name'] = '  Spaced Name  '
      expect(logic.display_name).to eq('Spaced Name')
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
          organization_instances: organization_instances
        )
      end

      it 'raises unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Authentication required/
        )
      end
    end

    context 'when display_name is empty' do
      let(:params) { { 'display_name' => '', 'description' => '', 'contact_email' => '' } }

      it 'raises form error for missing name' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Organization name is required/
        )
      end
    end

    context 'when display_name is too long' do
      let(:params) { { 'display_name' => 'x' * 101, 'description' => '', 'contact_email' => '' } }

      it 'raises form error for name too long' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /must be less than 100 characters/
        )
      end
    end

    context 'when description is too long' do
      let(:params) do
        { 'display_name' => 'Valid Name', 'description' => 'x' * 501, 'contact_email' => '' }
      end

      it 'raises form error for description too long' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Description must be less than 500 characters/
        )
      end
    end

    context 'when contact_email already exists' do
      before do
        allow(Onetime::Organization).to receive(:contact_email_exists?)
          .with('taken@example.com').and_return(true)
      end

      let(:params) do
        { 'display_name' => 'Valid Name', 'description' => '', 'contact_email' => 'taken@example.com' }
      end

      it 'raises form error for duplicate email' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /organization with this contact email already exists/
        )
      end
    end

    context 'with valid params' do
      before do
        allow(Onetime::Organization).to receive(:contact_email_exists?).and_return(false)
      end

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#check_organization_quota!' do
    let(:primary_org) do
      instance_double(
        Onetime::Organization,
        objid: 'org-primary',
        is_default: true,
        entitlements: entitlements
      )
    end

    let(:entitlements) { double('SortedSet', any?: has_entitlements) }
    let(:has_entitlements) { false }
    let(:organization_instances) { double('SortedSet', to_a: [primary_org], size: 1, first: primary_org) }

    before do
      allow(Onetime::Organization).to receive(:contact_email_exists?).and_return(false)
      allow(primary_org).to receive(:respond_to?).with(:at_limit?).and_return(true)
    end

    context 'when no primary organization exists (first org creation)' do
      let(:organization_instances) { double('SortedSet', to_a: [], size: 0, first: nil) }

      it 'skips quota check' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when billing is disabled (no entitlements)' do
      let(:has_entitlements) { false }

      it 'skips quota check (standalone mode)' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when billing is enabled and at limit', billing: true do
      let(:has_entitlements) { true }

      before do
        allow(primary_org).to receive(:at_limit?)
          .with('organizations', 1).and_return(true)
      end

      it 'raises upgrade_required error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to match(/Organization limit reached/)
        end
      end
    end

    context 'when billing is enabled and under limit', billing: true do
      let(:has_entitlements) { true }

      before do
        allow(primary_org).to receive(:at_limit?)
          .with('organizations', 1).and_return(false)
      end

      it 'allows organization creation' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    let(:new_organization) do
      instance_double(
        Onetime::Organization,
        objid: 'org-new-123',
        extid: 'ext-org-new',
        display_name: 'My Organization',
        description: '',
        contact_email: 'contact@example.com',
        is_default: false,
        created: Time.now.to_i,
        updated: Time.now.to_i,
        owner_id: 'cust-123',
        member_count: 1,
        save: true
      )
    end

    before do
      allow(Onetime::Organization).to receive(:contact_email_exists?).and_return(false)
      allow(Onetime::Organization).to receive(:create!)
        .and_return(new_organization)
      allow(new_organization).to receive(:description=)
      allow(new_organization).to receive(:owner?).with(customer).and_return(true)
    end

    it 'creates organization with display_name and customer' do
      expect(Onetime::Organization).to receive(:create!)
        .with('My Organization', customer, 'contact@example.com')
        .and_return(new_organization)
      logic.process
    end

    it 'sets description if provided' do
      expect(new_organization).to receive(:description=).with('A test organization')
      expect(new_organization).to receive(:save)
      logic.process
    end

    it 'returns success data with serialized organization' do
      result = logic.process
      expect(result).to have_key(:user_id)
      expect(result).to have_key(:record)
      expect(result[:user_id]).to eq('cust-123')
    end

    context 'when contact_email is empty' do
      let(:params) do
        { 'display_name' => 'My Organization', 'description' => '', 'contact_email' => '' }
      end

      it 'passes nil for contact_email' do
        expect(Onetime::Organization).to receive(:create!)
          .with('My Organization', customer, nil)
          .and_return(new_organization)
        logic.process
      end
    end
  end

  describe '#form_fields' do
    it 'returns hash with form field values' do
      fields = logic.form_fields
      expect(fields[:display_name]).to eq('My Organization')
      expect(fields[:description]).to eq('A test organization')
      expect(fields[:contact_email]).to eq('contact@example.com')
    end
  end
end
