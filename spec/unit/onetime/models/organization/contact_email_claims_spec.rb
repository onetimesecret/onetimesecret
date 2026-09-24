# spec/unit/onetime/models/organization/contact_email_claims_spec.rb
#
# frozen_string_literal: true

# Organization.find_contact_email_claims resolves the verbatim-keyed
# contact_email_index tolerantly. The default is a single-HGET fast path for
# provisioning; `exhaustive: true` keeps collecting after an exact hit so a
# second spelling of the same address held by a DIFFERENT organization is
# visible to the purge preflight's ambiguity refusal.
#
# Run: bundle exec rspec spec/unit/onetime/models/organization/contact_email_claims_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Organization, '.find_contact_email_claims' do
  let(:client) { double('Redis') }
  let(:index) { double('contact_email_index', dbkey: 'organization:contact_email_index', dbclient: client) }
  let(:stored) { {} }

  before do
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(index)
    allow(index).to receive(:get) { |key| stored[key] }
    allow(client).to receive(:hscan) do |_dbkey, _cursor, **_options|
      ['0', stored.to_a]
    end
  end

  it 'returns the exact hit without scanning by default' do
    stored['user@example.com'] = 'org-a'

    claims = Onetime::Organization.find_contact_email_claims('user@example.com')

    expect(claims).to eq('user@example.com' => 'org-a')
    expect(client).not_to have_received(:hscan)
  end

  it 'scans when neither spelling is stored exactly' do
    stored['User@Example.com'] = 'org-a'

    claims = Onetime::Organization.find_contact_email_claims('user@example.com')

    expect(claims).to eq('User@Example.com' => 'org-a')
    expect(client).to have_received(:hscan).once
  end

  it 'keeps collecting after an exact hit when exhaustive' do
    stored['user@example.com']  = 'org-a'
    stored['User@Example.com']  = 'org-b'
    stored['other@example.com'] = 'org-c'

    claims = Onetime::Organization.find_contact_email_claims('user@example.com', exhaustive: true)

    expect(claims).to eq('user@example.com' => 'org-a', 'User@Example.com' => 'org-b')
    expect(client).to have_received(:hscan).once
  end

  it 'hides the second spelling on the fast path, which is why the preflight asks for exhaustive' do
    stored['user@example.com'] = 'org-a'
    stored['User@Example.com'] = 'org-b'

    claims = Onetime::Organization.find_contact_email_claims('user@example.com')

    expect(claims).to eq('user@example.com' => 'org-a')
  end

  it 'resolves a single holder id from every spelling' do
    stored['User@Example.com'] = 'org-a'

    expect(Onetime::Organization.find_contact_email_holder_id('user@example.com')).to eq('org-a')
  end
end
