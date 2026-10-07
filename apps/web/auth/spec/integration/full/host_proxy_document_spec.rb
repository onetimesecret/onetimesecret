# apps/web/auth/spec/integration/full/host_proxy_document_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack) — host and proxy simulation matrix,
# the HTML document the core app serves (#4223)
# =============================================================================
#
# GET / on each shape, and two things the document carries that name a host:
#
#   csp       whether the Content-Security-Policy header's form-action names
#             the tenant's IdP origin. Onetime::Middleware::TenantCspExtras
#             widens it from env['onetime.display_domain'] (#4173); it does
#             not read Rack's host, so the rewrite changes nothing here.
#   og_title  the og:title meta tag: the display domain, or the brand
#             product name when there is none.
#   og_image  whether the install's social card is emitted. It is not on a
#             request that classified :custom (#4150), and it is on every
#             other one, an unverified or unreadable tenant name included.
#
# Every row also checks og:url and twitter:domain. Both render from
# configured site.host (apps/web/core/views/helpers/initialize_view_vars.rb,
# `baseuri`), on a tenant page as on the canonical one. THIS FILE PINS
# CURRENT BEHAVIOUR: a tenant page advertising the canonical og:url is what
# ships today.
#
# RUN:
#   tests/lanes/run full-sqlite --only \
#     apps/web/auth/spec/integration/full/host_proxy_document_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/host_proxy_matrix_support'

module HostProxyMatrix
  TENANT_IDP_ORIGIN = 'https://login.microsoftonline.com'

  DOCUMENT_ROWS = [
    shape(:canonical_host, id: 'P01', case: 'canonical host', csp: false, og_title: '{canonical}', og_image: true),
    shape(:tenant_host, id: 'P02', case: 'verified custom domain in Host', csp: true, og_title: '{tenant}',
      og_image: false),
    shape(:tenant_forwarded, id: 'P03', case: 'tenant in X-Forwarded-Host', csp: true, og_title: '{tenant}',
      og_image: false),
    shape(:tenant_forwarded_port, id: 'P04', case: 'tenant and a public port in X-Forwarded-Host',
      csp: true, og_title: '{tenant}', og_image: false),
    shape(:doubled_tenant, id: 'P05', case: 'doubled verified custom domain Host', csp: true, og_title: '{tenant}',
      og_image: false),
    shape(:forwarded_public_peer, id: 'P06', case: 'X-Forwarded-Host from a public peer',
      csp: false, og_title: '{canonical}', og_image: true),
    shape(:rfc7239_tenant, id: 'P07', case: 'Forwarded host= names the tenant', csp: false, og_title: '{canonical}',
      og_image: true),
    shape(:unregistered_forwarded, id: 'P08', case: 'unregistered forwarded host', csp: false, og_title: UNREGISTERED,
      og_image: true),
    shape(:unverified_forwarded, id: 'P09', case: 'unverified custom domain in X-Forwarded-Host',
      csp: false, og_title: '{tenant}', og_image: false),
    shape(:read_fails_forwarded, id: 'P10', case: 'read failure, tenant in X-Forwarded-Host',
      csp: false, og_title: '{tenant}', og_image: true),
  ].freeze
end

RSpec.describe 'Host and proxy simulation matrix: the served document (#4223)',
  :shared_db_state, type: :integration do
  include_context 'host proxy rows'

  def meta(doc, selector)
    doc.css(selector).first&.[]('content')
  end

  def form_action_of(csp)
    csp.to_s.split(';').map(&:strip).find { |directive| directive.start_with?('form-action') }.to_s
  end

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'
      include_context 'domains enabled'

      let(:matrix_canonical_host) { canonical_host }

      # SSO on for the tenant, so TenantSsoResolution yields its config.
      before do
        Onetime::CustomDomain::SigninConfig.create!(
          domain_id: test_custom_domain.identifier,
          enabled: true,
          signin_enabled: true,
          sso_enabled: true,
        )
      end

      after { Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier) }

      HostProxyMatrix::DOCUMENT_ROWS.each do |row|
        it HostProxyMatrix.row_name(row) do
          prepare_record(row[:record])
          apply_topology(row)
          header 'Accept', 'text/html'

          get '/'

          expect(last_response.status).to eq(200),
            "#{row[:id]}: expected 200, got #{last_response.status} #{last_response.headers['Location'].inspect}"
          expect(last_response.content_type.to_s).to start_with('text/html')
          expect_rewrite_record(row)

          csp         = last_response.headers['content-security-policy']
          form_action = form_action_of(csp)
          expect(csp).not_to be_nil, "#{row[:id]}: no Content-Security-Policy header"
          if row[:csp]
            expect(form_action).to include(HostProxyMatrix::TENANT_IDP_ORIGIN), "#{row[:id]}: #{form_action.inspect}"
          else
            expect(form_action).not_to include(HostProxyMatrix::TENANT_IDP_ORIGIN), "#{row[:id]}: #{form_action.inspect}"
          end
          expect(form_action).not_to include(',')

          doc = Nokogiri::HTML(last_response.body)
          expect(meta(doc, 'meta[property="og:title"]')).to eq(fill(row[:og_title]))
          expect(meta(doc, 'meta[property="og:url"]')).to eq(HostProxyMatrix::SITE_HOST_ORIGIN)
          expect(meta(doc, 'meta[property="twitter:domain"]')).to eq(HostProxyMatrix::SITE_HOST)
          expect(doc.css('meta[property="og:image"]').empty?).to eq(!row[:og_image]), "#{row[:id]}: og:image"
        end
      end
    end
  end
end
