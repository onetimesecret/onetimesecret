# apps/api/domains/spec/integration/simple/add_domain_refusals_spec.rb
#
# frozen_string_literal: true

# POST /api/domains/add when the model refuses the domain.
#
# CustomDomain.parse and CustomDomain.create! refuse some names with an
# Onetime::Problem whose message is meant for the customer: a domain nested
# deeper than MAX_SUBDOMAIN_DEPTH, a domain whose TXT challenge record name
# would not fit the DNS name limits, a name that is already registered. These
# reach the customer as a 422 form error carrying that message.
#
# A datastore failure during create! is not bad input: it is a 503 with
# Retry-After, so the client retries instead of showing a form error.
#
# Runs through the full Rack::URLMap with a real session (simple auth mode).

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')
require 'delegate'

RSpec.describe 'POST /api/domains/add refusals', type: :integration do
  include Rack::Test::Methods
  include CsrfTestHelpers

  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:test_password) { 'Test123!@#' }

  let!(:owner) do
    customer = Onetime::Customer.new(email: "add-refusal-#{test_run_id}@test.local")
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role     = 'customer'
    customer.save
    customer
  end

  let!(:organization) do
    Onetime::Organization.create!("Add Refusal Org #{test_run_id}", owner, "contact-#{test_run_id}@test.local")
  end

  after do
    organization.list_domains.each(&:destroy!)
    organization.destroy!
    owner.destroy!
  end

  def login_as(customer)
    reset_csrf_token
    csrf_post '/auth/login', { login: customer.email, password: test_password }
    reset_csrf_token
  end

  def add_domain(name)
    csrf_post '/api/domains/add', { domain: name }
    [last_response.status, JSON.parse(last_response.body)['error']]
  end

  before { login_as(owner) }

  it 'adds an ordinary domain (control)' do
    expect(add_domain("shop-#{test_run_id}.example.com").first).to eq(200)
  end

  it 'refuses a domain nested too deep with a 422 and the reason' do
    name = "#{(['a'] * 10).join('.')}.d#{test_run_id}.example.com"

    expect(add_domain(name)).to eq([422, 'Domain too deep (max: 10)'])
  end

  it 'refuses a domain whose TXT challenge record name would not fit with a 422 and the reason' do
    name = "#{(['a' * 63] * 3).join('.')}.#{'b' * 15}#{test_run_id}.com" # 227 bytes

    expect(add_domain(name)).to eq([422, 'Domain too long for its TXT validation record'])
  end

  it 'refuses a name create! turns down with a 422 and the reason' do
    allow(Onetime::CustomDomain).to receive(:create!)
      .and_raise(Onetime::Problem, 'Domain is registered to another organization')

    expect(add_domain("taken-#{test_run_id}.example.com")).to eq([422, 'Domain is registered to another organization'])
  end

  # A record with no organization (an orphan) is not handed to whoever adds
  # its name. The reply is the one for a name another organization holds,
  # and nothing is written or requested for the name.
  context 'when the name belongs to an orphaned record' do
    let(:earlier_owner) do
      Onetime::Organization.new(display_name: "Earlier Owner #{test_run_id}").tap(&:save)
    end
    let(:strategy) { double('DomainValidationStrategy', request_certificate: { status: 'requested' }) }
    let(:orphan_name) { "orphan-#{test_run_id}.example.com" }

    let!(:orphaned) do
      rec = Onetime::CustomDomain.create!(orphan_name, earlier_owner.objid)
      rec.remove_from_organization_domains(earlier_owner)
      Familia.dbclient.hdel(rec.dbkey, 'org_id')
      Onetime::CustomDomain.owners.remove(rec.to_s)
      Onetime::CustomDomain.find_by_identifier(rec.identifier)
    end

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(strategy)
    end

    after do
      Onetime::CustomDomain.find_by_identifier(orphaned.identifier)&.destroy!
      earlier_owner.destroy! if earlier_owner.exists?
    end

    it 'refuses with a 422 and the cross-organization text, and requests no certificate' do
      stored = Familia.dbclient.hgetall(orphaned.dbkey)
      allow(Onetime::CustomDomain).to receive(:create!).and_call_original

      expect(add_domain(orphan_name)).to eq([422, 'Domain is registered to another organization'])
      # Refused by the pre-check, before create! is reached.
      expect(Onetime::CustomDomain).not_to have_received(:create!)
      expect(strategy).not_to have_received(:request_certificate)
      expect([Familia.dbclient.hgetall(orphaned.dbkey) == stored, organization.domain_count]).to eq([true, 0])
    end
  end

  it 'answers a datastore failure during create! with a 503 and Retry-After, not a form error' do
    failing = Class.new(SimpleDelegator) do
      define_method(:claim_field) { |*| raise Redis::CannotConnectError, 'datastore unreachable' }
    end
    index = Onetime::CustomDomain.canonical_display_domain_index
    allow(Onetime::CustomDomain).to receive(:canonical_display_domain_index).and_return(failing.new(index))
    name = "outage-#{test_run_id}.example.com"

    status, = add_domain(name)

    expect([status, last_response.headers['Retry-After'], Onetime::CustomDomain.load_by_display_domain(name)])
      .to eq([503, '5', nil])
  end
end
