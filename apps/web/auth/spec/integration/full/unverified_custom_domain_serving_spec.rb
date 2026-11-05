# apps/web/auth/spec/integration/full/unverified_custom_domain_serving_spec.rb
#
# frozen_string_literal: true

# A registered custom domain whose ownership is not verified is not served
# under a validation strategy that checks ownership: every request to its host
# answers DomainStrategy's 404 through the whole mounted stack (web, auth and
# API apps alike), and nothing below DomainStrategy runs. The same host is
# served once verified, under passthrough, and with
# features.domains.serve_unverified.
#
# Run: tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/unverified_custom_domain_serving_spec.rb
require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'

# rubocop:disable-next RSpec/SpecFilePathFormat -- full-mode lane owns this integration directory
RSpec.describe 'Custom domain serving before ownership is verified', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include_context 'domains enabled'
  include_context 'tenant fixtures'

  before(:all) { boot_onetime_app }

  let(:not_configured) { 'This domain is not configured' }

  # GET and POST paths across the mounted apps: the web shell, the Rodauth
  # app, tenant SSO initiation, and an anonymous API.
  tenant_requests = [
    [:get, '/'],
    [:get, '/signin'],
    [:post, '/auth/login'],
    [:post, '/auth/sso/entra'],
    [:get, '/api/incoming/config'],
    [:post, '/api/incoming/secret'],
  ].freeze

  def configure_domains(**settings)
    settings.each { |key, value| OT.conf['features']['domains'][key.to_s] = value }
  end

  def unverify!(domain)
    domain.ownership_verified = false
    domain.save
  end

  before do
    Onetime::CustomDomain.reset_serving_policy!
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: test_custom_domain.identifier,
      enabled: true,
      signin_enabled: true,
      sso_enabled: true,
    )
    header 'Host', tenant_domain
  end

  after do
    Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
    Onetime::CustomDomain.reset_serving_policy!
  end

  context 'under approximated, with ownership not verified' do
    before do
      configure_domains(validation_strategy: 'approximated', serve_unverified: false)
      unverify!(test_custom_domain)
    end

    tenant_requests.each do |verb, path|
      it "answers #{verb.upcase} #{path} with the fixed 404" do
        send(verb, path)

        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq(not_configured)
        expect(last_response.headers['cache-control']).to eq('no-store')
        expect(last_response.headers.keys.map(&:downcase)).not_to include('o-domain-strategy', 'o-display-domain')
        expect(last_response.headers['location']).to be_nil
        expect(last_request.env.keys.grep(/\Aonetime\.(domain_strategy|custom_domain)/)).to be_empty
      end
    end

    it 'does not affect the canonical host' do
      header 'Host', canonical_host
      get '/api/incoming/config'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('canonical')
    end

    it 'serves the host again once its ownership is verified' do
      test_custom_domain.ownership_verified = true
      test_custom_domain.save

      get '/api/incoming/config'

      expect(last_response.status).to eq(200)
      expect(last_request.env['onetime.domain_strategy']).to eq(:custom)
      expect(last_request.env['onetime.custom_domain_id']).to eq(test_custom_domain.identifier)
    end
  end

  context 'under caddy_on_demand, with ownership not verified' do
    before do
      configure_domains(validation_strategy: 'caddy_on_demand', serve_unverified: false)
      unverify!(test_custom_domain)
    end

    it 'answers 404 and starts no SSO' do
      post '/auth/sso/entra'

      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq(not_configured)
      expect(last_response.headers['location']).to be_nil
    end
  end

  context 'under approximated, with ownership verified' do
    before { configure_domains(validation_strategy: 'approximated', serve_unverified: false) }

    it 'serves the host' do
      get '/api/incoming/config'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('custom')
    end

    it 'starts tenant SSO at the IdP' do
      post '/auth/sso/entra'

      expect(last_response.status).to eq(302)
      expect(URI.parse(last_response.headers.fetch('Location')).host).to eq('login.microsoftonline.com')
    end
  end

  context 'under passthrough, with ownership not verified' do
    before do
      configure_domains(validation_strategy: 'passthrough', serve_unverified: false)
      unverify!(test_custom_domain)
    end

    it 'serves the host: registration is the basis' do
      get '/api/incoming/config'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('custom')
    end

    it 'still refuses tenant SSO until a verify call marks the domain verified' do
      post '/auth/sso/entra'

      expect(last_response.status).to eq(302)
      location = URI.parse(last_response.headers.fetch('Location'))
      expect(location.host).to be_nil.or eq(tenant_domain)
      expect(CGI.parse(location.query.to_s)['auth_error']).to eq(['sso_domain_unverified'])
    end
  end

  context 'with features.domains.serve_unverified true' do
    before do
      configure_domains(validation_strategy: 'approximated', serve_unverified: true)
      unverify!(test_custom_domain)
    end

    it 'serves the host whatever its ownership state' do
      get '/api/incoming/config'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('custom')
    end
  end
end
