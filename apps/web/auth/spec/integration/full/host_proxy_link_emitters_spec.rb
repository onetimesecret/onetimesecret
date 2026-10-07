# apps/web/auth/spec/integration/full/host_proxy_link_emitters_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack) — host and proxy simulation matrix,
# the link emitters the first emitter table does not drive (#4223)
# =============================================================================
#
# Three emitters, each under the shapes of support/host_proxy_matrix_support.rb,
# with public_host_rewrite off and on:
#
#   1. The sso-link-confirm email. An SSO callback for an existing account
#      that has no password to challenge mints a single-use token and emails
#      it (config/hooks/omniauth.rb). The confirm URL and the mail's baseuri
#      come from Rodauth `base_url`, the Auth::PublicHost chain; the mail's
#      display_domain from `public_display_domain`. The email is issued on
#      the platform surface only: a tenant-surface callback refuses (H-3).
#
#   2. Secret links. POST /api/v1/share resolves the link's domain from the
#      request body and the display domain (V1 BaseSecretAction), stores it
#      on the receipt, and the receipt read and the secret_link email build
#      the link from it. None of them reads Rack's host.
#
#   3. Billing. The checkout and portal URLs are built from configured
#      site.host (apps/web/billing: billing_base_url, CreateCheckoutLink
#      .base_url) and the guard redirects are relative paths. Nothing in
#      the billing app reads a request host. The rows pin that the plan
#      redirect carries no host on a tenant request.
#
# THIS FILE PINS CURRENT BEHAVIOUR.
#
# RUN:
#   tests/lanes/run full-sqlite --only \
#     apps/web/auth/spec/integration/full/host_proxy_link_emitters_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/host_proxy_matrix_support'

module HostProxyMatrix
  # link      origin of the emailed confirm URL; nil when no email is sent
  # brand     the display_domain the mail is rendered for
  # callback  origin of the callback URL the request phase redirects to (in
  #           OmniAuth test mode the request phase goes straight there);
  #           the same as `link` unless the row names it
  # location  suffix of the callback's Location
  LINK_CONFIRM_ROWS = [
    shape(:canonical_host, id: 'L01', case: 'canonical host',
      link: CANONICAL_ORIGIN, brand: '{canonical}', location: '/signin?auth_notice=link_verification_sent'),
    shape(:canonical_port, id: 'L02', case: 'canonical host with a non-default port',
      link: 'https://{canonical}:8443', brand: '{canonical}', location: '/signin?auth_notice=link_verification_sent'),
    shape(:doubled_canonical, id: 'L03', case: 'doubled canonical Host',
      link: CANONICAL_ORIGIN, brand: '{canonical}', location: '/signin?auth_notice=link_verification_sent'),
    shape(:rfc7239_tenant, id: 'L04', case: 'Forwarded host= names the tenant',
      link: CANONICAL_ORIGIN, brand: '{canonical}', location: '/signin?auth_notice=link_verification_sent'),
    # A public peer's X-Forwarded-Proto is dropped (matrix row U01): the
    # link builds on the http scheme of the connection.
    shape(:forwarded_public_peer, id: 'L05', case: 'X-Forwarded-Host from a public peer',
      link: 'http://{canonical}', brand: '{canonical}', location: '/signin?auth_notice=link_verification_sent'),
    # The tenant surface does not mint a mailbox proof.
    shape(:tenant_forwarded, id: 'L06', case: 'tenant in X-Forwarded-Host refuses on the tenant surface',
      link: nil, callback: TENANT_ORIGIN, location: '/signin?auth_error=tenant_sso_link_unavailable'),
    shape(:tenant_host, id: 'L07', case: 'verified custom domain in Host refuses on the tenant surface',
      link: nil, callback: TENANT_ORIGIN, location: '/signin?auth_error=tenant_sso_link_unavailable'),
  ].freeze

  # share_domain  the domain named in the request body (nil: none)
  # recipient     when set, the secret_link email is expected. Sending
  #               requires an account, so the row authenticates as the
  #               organization owner (Basic auth, the V1 API's own scheme).
  # status        response status; 200 is a created link, 404 the API's
  #               refusal of a domain the caller may not use (#3311)
  # domain        the share domain the receipt carries (nil: none; the API
  #               serializes it as '' and the links build on site.host)
  SHARE_ROWS = [
    shape(:canonical_host, id: 'S01', case: 'canonical host, no share domain', status: 200, domain: nil),
    shape(:tenant_forwarded, id: 'S02', case: 'tenant in X-Forwarded-Host, no share domain',
      status: 200, domain: '{tenant}'),
    shape(:tenant_host, id: 'S03', case: 'verified custom domain in Host, no share domain',
      status: 200, domain: '{tenant}'),
    shape(:tenant_forwarded_port, id: 'S04', case: 'tenant and a public port in X-Forwarded-Host',
      status: 200, domain: '{tenant}'),
    shape(:doubled_tenant, id: 'S05', case: 'doubled verified custom domain Host', status: 200, domain: '{tenant}'),
    shape(:tenant_forwarded, id: 'S06', case: 'tenant in X-Forwarded-Host naming another verified domain',
      share_domain: '{other}', status: 404),
    shape(:canonical_host, id: 'S07', case: 'canonical host naming the tenant', share_domain: '{tenant}', status: 404),
    shape(:tenant_forwarded, id: 'S08', case: 'tenant in X-Forwarded-Host, owner sends to a recipient',
      recipient: true, auth: :owner, status: 200, domain: '{tenant}'),
    shape(:forwarded_public_peer, id: 'S09', case: 'X-Forwarded-Host from a public peer', status: 200, domain: nil),
    shape(:unregistered_forwarded, id: 'S10', case: 'unregistered forwarded host', status: 200, domain: nil),
    shape(:unverified_forwarded, id: 'S11', case: 'unverified custom domain in X-Forwarded-Host',
      status: 200, domain: '{tenant}'),
    shape(:read_fails_forwarded, id: 'S12', case: 'read failure, tenant in X-Forwarded-Host',
      status: 200, domain: nil),
  ].freeze

  BILLING_ROWS = [
    shape(:canonical_host, id: 'B01', case: 'canonical host'),
    shape(:tenant_forwarded, id: 'B02', case: 'tenant in X-Forwarded-Host'),
    shape(:tenant_forwarded_port, id: 'B03', case: 'tenant and a public port in X-Forwarded-Host'),
    shape(:doubled_tenant, id: 'B04', case: 'doubled verified custom domain Host'),
  ].freeze
end

RSpec.describe 'Host and proxy simulation matrix: link emitters (#4223)', :shared_db_state, type: :integration do
  include_context 'host proxy rows'

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'
      include_context 'domains enabled'

      let(:matrix_canonical_host) { canonical_host }

      # ----------------------------------------------------------------------
      describe 'the sso-link-confirm email' do
        let(:account_email) { unique_test_email('linkconfirm') }
        let(:uid) { "entra-#{test_run_id}" }

        # A verified account with no password: the mailbox-proof branch.
        # The paired Customer resolves the watermark the hook records.
        let!(:account_id) do
          normalized = OT::Utils.normalize_email(account_email)
          customer   = Onetime::Customer.new(email: normalized)
          customer.save
          auth_db[:accounts].insert(
            email: normalized,
            status_id: AuthTestConstants::STATUS_VERIFIED,
            external_id: customer.extid,
          )
        end

        # Tenant SSO on, so a tenant-surface row reaches the callback (and
        # its refusal) instead of being turned away at initiation.
        before do
          Onetime::CustomDomain::SigninConfig.create!(
            domain_id: test_custom_domain.identifier,
            enabled: true,
            signin_enabled: true,
            sso_enabled: true,
          )
          enable_platform_fallback
          allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
          @delivered = []
          allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **opts|
            @delivered << { template: template, data: data, opts: opts }
            true
          end
          enable_omniauth_test_mode
          mock_entra_success(email: account_email, uid: uid)
          # The mock strategy has no injected credentials to resolve an
          # issuer from, and a tenant-surface callback without one is refused
          # as issuerless before it reaches the account branch. Name one the
          # way Entra's id_token does.
          OmniAuth.config.mock_auth[:entra].extra.raw_info[:iss] =
            "https://login.microsoftonline.com/#{test_sso_config.tenant_id}/v2.0"
        end

        after do
          teardown_mock_auth
          Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
          clear_auth_database
        end

        HostProxyMatrix::LINK_CONFIRM_ROWS.each do |row|
          it HostProxyMatrix.row_name(row) do
            expected = row_for_run(row)
            prepare_record(row[:record])
            apply_topology(row)

            # Request phase first: on a tenant it binds the surface the
            # callback runs on. In OmniAuth test mode it redirects straight
            # to the callback.
            post '/auth/sso/entra'
            expect(last_response.status).to eq(302)
            expect(last_response.headers['Location'])
              .to eq("#{fill(expected.fetch(:callback, expected[:link]))}/auth/sso/entra/callback")
            clear_body_headers
            post '/auth/sso/entra/callback'

            expect(last_response.status).to eq(302),
              "#{row[:id]}: #{last_response.status} #{last_response.body.to_s[0, 200]}"
            expect(last_response.headers['Location'].to_s).to end_with(expected[:location])
            expect_rewrite_record(row)

            if expected[:link].nil?
              expect(@delivered).to be_empty
              next
            end

            expect(@delivered.size).to eq(1), "#{row[:id]}: #{@delivered.inspect}"
            mail = @delivered.first
            expect(mail[:template]).to eq(:sso_link_verification)
            expect(origin_of(mail[:data][:confirm_url])).to eq(fill(expected[:link]))
            expect(mail[:data][:confirm_url]).to start_with("#{fill(expected[:link])}/sso-link-confirm/")
            expect(mail[:data][:baseuri]).to eq(fill(expected[:link]))
            expect(mail[:data][:display_domain]).to eq(fill(expected[:brand]))
            expect(mail[:data][:confirm_url]).not_to include(',')
          end
        end
      end

      # ----------------------------------------------------------------------
      describe 'secret links' do
        let(:other_domain) { "other-#{test_run_id}.acme-corp.example.com" }

        # Guests may create links on the tenant: a homepage configuration in
        # create mode is what allow_public_secret_creation? reads.
        let!(:homepage_config) do
          Onetime::CustomDomain::HomepageConfig.create!(
            domain_id: test_custom_domain.identifier, enabled: true, secrets_mode: 'create',
          )
        end

        # A second verified custom domain, for the rows that name one.
        let!(:other_custom_domain) do
          domain = Onetime::CustomDomain.new(display_domain: other_domain, org_id: test_organization.org_id)
          domain.verified = true
          domain.save
          Onetime::CustomDomain.display_domain_index.put(other_domain, domain.domainid)
          domain
        end

        before do
          @delivered = []
          allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **opts|
            @delivered << { template: template, data: data, opts: opts }
            true
          end
        end

        after do
          Onetime::CustomDomain::HomepageConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
          Onetime::CustomDomain.display_domain_index.remove(other_domain) rescue nil
          other_custom_domain&.destroy!
        end

        def fill_domain(value)
          fill(value.to_s.gsub('{other}', other_domain))
        end

        # The organization's owner, with an API token for Basic auth.
        let(:owner) do
          customer = Onetime::Customer.find_by_email("owner-#{test_run_id}@test.local")
          customer.apitoken = SecureRandom.hex(20)
          customer.save
          customer
        end

        # The origin the receipt's links build on: the share domain, or
        # site.host when there is none.
        def link_origin_for(domain)
          domain.to_s.empty? ? HostProxyMatrix::SITE_HOST_ORIGIN : "https://#{domain}"
        end

        HostProxyMatrix::SHARE_ROWS.each do |row|
          it HostProxyMatrix.row_name(row) do
            expected = row_for_run(row)
            prepare_record(row[:record])
            apply_topology(row)

            params = { secret: "matrix secret #{row[:id]}", ttl: 3600 }
            params[:share_domain] = fill_domain(row[:share_domain]) if row[:share_domain]
            params[:recipient]    = unique_test_email('recipient') if row[:recipient]
            basic_authorize(owner.email, owner.apitoken) if row[:auth] == :owner

            post '/api/v1/share', params

            expect(last_response.status).to eq(expected[:status]),
              "#{row[:id]}: #{last_response.status} #{last_response.body.to_s[0, 300]}"
            expect_rewrite_record(row)
            next unless expected[:status] == 200

            domain  = fill(expected[:domain].to_s)
            created = JSON.parse(last_response.body)
            expect(created['share_domain']).to eq(domain), "#{row[:id]}: #{created.inspect}"
            expect(origin_of(created['metadata_url'])).to eq(link_origin_for(domain))
            expect(created['metadata_url']).to end_with("/receipt/#{created['metadata_key']}")
            expect(created['metadata_url']).not_to include(',')

            # The receipt read, with the same shape.
            clear_body_headers
            apply_topology(row)
            basic_authorize(owner.email, owner.apitoken) if row[:auth] == :owner
            get "/api/v1/receipt/#{created['metadata_key']}"
            expect(last_response.status).to eq(200), "#{row[:id]}: #{last_response.status} #{last_response.body.to_s[0, 300]}"
            receipt = JSON.parse(last_response.body)
            expect(receipt['share_domain']).to eq(domain), "#{row[:id]}: #{receipt.inspect}"
            # The read's own metadata_url builds on site.host whatever the
            # share domain, unlike the one the create response carries: V1
            # logic takes `domains_enabled` from site.domains.enabled
            # (apps/api/v1/logic/base.rb), a key the configuration no longer
            # has, so ShowReceipt never uses the receipt's share domain.
            # Pinned as observed.
            expect(origin_of(receipt['metadata_url'])).to eq(HostProxyMatrix::SITE_HOST_ORIGIN)

            next unless row[:recipient]

            expect(@delivered.size).to eq(1), "#{row[:id]}: #{@delivered.inspect}"
            mail = @delivered.first
            expect(mail[:template]).to eq(:secret_link)
            expect(mail[:data][:share_domain]).to eq(domain)
            text = Onetime::Mail::Templates::SecretLink.new(mail[:data]).render_text
            expect(text).to include("#{link_origin_for(domain)}/secret/#{created['secret_key']}")
          end
        end
      end

      # ----------------------------------------------------------------------
      # Billing is off for every example unless it is tagged (billing spec
      # support, billing_isolation.rb), and the stack the other rows use was
      # mounted without the billing app. So these rows mount the billing
      # application themselves. It builds the same middleware stack every
      # application does (DetectHost, StripForwardedHost, DomainStrategy,
      # PublicHostRewrite), which is what the rows are about.
      describe 'billing redirects', billing: true do
        before(:all) { require File.expand_path('../../../../billing/application', __dir__) }

        def app
          @billing_stack ||= Rack::URLMap.new('/billing' => Billing::Application.new)
        end

        HostProxyMatrix::BILLING_ROWS.each do |row|
          it HostProxyMatrix.row_name(row) do
            apply_topology(row)

            get '/billing/plans/identity/month'

            expect(last_response.status).to eq(302), "#{row[:id]}: #{last_response.status}"
            expect(last_response.headers['Location']).to eq('/signup?product=identity&interval=month')
            expect_rewrite_record(row)

            # The Stripe return URLs are configuration, whatever the request.
            expect(Billing::Operations::CreateCheckoutLink.base_url).to eq(HostProxyMatrix::SITE_HOST_ORIGIN)
          end
        end
      end
    end
  end
end
