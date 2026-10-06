# apps/web/auth/spec/integration/full/host_proxy_origin_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack) — host and proxy simulation matrix,
# the Origin check on SSO initiation (#4223, the rows #4542 asks for)
# =============================================================================
#
# POST /auth/sso/entra is a browser form submission. Before the SSO route
# runs, Rack::Protection::HttpOrigin admits or refuses the request on its
# Origin header. Two admission paths apply to an initiation POST:
#
#   1. rack-protection's own check: Origin equals Rack::Request#base_url,
#      which is scheme://host[:port] of the request Rack sees. Behind a
#      Host-rewriting proxy that is the origin hop unless PublicHostRewrite
#      is on.
#   2. Onetime::Middleware::HttpOriginOptions::ALLOW_IF: Origin equals
#      https://{display domain}, with no port.
#
# Each row sends one shape from the matrix with one Origin and states the
# status: 302 (the IdP redirect, or an auth_error redirect when the route
# refuses) or 403 (HttpOrigin refused). `rewritten:` names the status that
# differs with the rewrite on, which is where path 1 changes.
#
# THIS FILE PINS CURRENT BEHAVIOUR. Two rows record findings:
#
#   G04  a tenant Origin that carries a public port is refused with the
#        rewrite off (neither path matches it) and admitted with it on.
#   G08  an Origin naming the origin target is admitted on a tenant request
#        with the rewrite off (path 1 matches the raw Host) and refused with
#        it on.
#
# RUN:
#   tests/lanes/run full-sqlite --only \
#     apps/web/auth/spec/integration/full/host_proxy_origin_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/host_proxy_matrix_support'

module HostProxyMatrix
  FOREIGN_ORIGIN = 'https://evil.attacker.example'

  # origin   the Origin header sent
  # status   response status with the rewrite off
  # idp      :platform or :tenant when the 302 is an IdP redirect; nil when
  #          it is an auth_error redirect (then `location` is its suffix)
  ORIGIN_ROWS = [
    shape(:canonical_host, id: 'G01', case: 'canonical host, Origin names it',
      origin: CANONICAL_ORIGIN, status: 302, idp: :platform),
    shape(:tenant_host, id: 'G02', case: 'verified custom domain in Host, Origin names it',
      origin: TENANT_ORIGIN, status: 302, idp: :tenant),
    shape(:tenant_forwarded, id: 'G03', case: 'tenant in X-Forwarded-Host, Origin names the tenant',
      origin: TENANT_ORIGIN, status: 302, idp: :tenant),
    # Neither admission path matches an Origin with a port until the rewrite
    # makes Rack's base_url the public authority.
    shape(:tenant_forwarded_port, id: 'G04', case: 'forwarded public port, Origin names the tenant with the port',
      origin: 'https://{tenant}:8443', status: 403,
      rewritten: { status: 302, idp: :tenant }),
    shape(:canonical_port, id: 'G05', case: 'canonical host on a port, Origin names it with the port',
      origin: 'https://{canonical}:8443', status: 302, idp: :platform),
    shape(:canonical_host, id: 'G06', case: 'Origin: null on the canonical host',
      origin: 'null', status: 403),
    shape(:tenant_forwarded, id: 'G07', case: 'Origin: null on a tenant request',
      origin: 'null', status: 403),
    # The raw Host is the origin target. rack-protection compares Origin
    # with Rack's base_url, which is that target until the rewrite replaces
    # it with the tenant.
    shape(:tenant_forwarded, id: 'G08', case: 'tenant in X-Forwarded-Host, Origin names the origin target',
      origin: CANONICAL_ORIGIN, status: 302, idp: :tenant,
      rewritten: { status: 403, idp: nil }),
    shape(:tenant_forwarded, id: 'G09', case: 'tenant in X-Forwarded-Host, Origin names the tenant over http',
      origin: 'http://{tenant}', status: 403),
    shape(:tenant_forwarded, id: 'G10', case: 'tenant in X-Forwarded-Host, foreign Origin',
      origin: FOREIGN_ORIGIN, status: 403),
    shape(:canonical_host, id: 'G11', case: 'canonical host, foreign Origin',
      origin: FOREIGN_ORIGIN, status: 403),
    shape(:doubled_tenant, id: 'G12', case: 'doubled verified custom domain Host, Origin names the tenant',
      origin: TENANT_ORIGIN, status: 302, idp: :tenant),
    # ALLOW_IF admits https://{display domain} for a display domain that
    # classified :invalid (H-03 in tools/host-seam/follow-up-validation.md).
    # The SSO route then refuses the request.
    shape(:unregistered_forwarded, id: 'G13', case: 'unregistered forwarded host, Origin names it (H-03)',
      origin: "https://#{UNREGISTERED}", status: 302, location: '/signin?auth_error=sso_not_configured'),
    # Admitted by ALLOW_IF (the record exists, so the display domain is the
    # tenant). With no sign-in configuration the gate answers 404 for an
    # unverified tenant (#4517; the emitter matrix's E11 configures sign-in
    # and gets the sso_domain_unverified redirect instead).
    shape(:unverified_forwarded, id: 'G14', case: 'unverified custom domain, Origin names it',
      origin: TENANT_ORIGIN, status: 404),
    shape(:read_fails_forwarded, id: 'G15', case: 'read failure, Origin names the tenant',
      origin: TENANT_ORIGIN, status: 302, location: '/signin?auth_error=sso_failed'),
    shape(:forwarded_public_peer, id: 'G16', case: 'X-Forwarded-Host from a public peer, Origin names the tenant',
      origin: TENANT_ORIGIN, status: 403),
  ].freeze
end

RSpec.describe 'Host and proxy simulation matrix: Origin on SSO initiation (#4223)',
  :shared_db_state, type: :integration do
  include_context 'host proxy rows'

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'
      include_context 'domains enabled'

      let(:matrix_canonical_host) { canonical_host }

      HostProxyMatrix::ORIGIN_ROWS.each do |row|
        it HostProxyMatrix.row_name(row) do
          expected = row_for_run(row)
          prepare_record(row[:record])
          apply_topology(row)
          header 'Origin', fill(row[:origin])

          post '/auth/sso/entra'

          expect(last_response.status).to eq(expected[:status]),
            "#{row[:id]}: expected #{expected[:status]}, got #{last_response.status} " \
            "#{last_response.headers['Location'].inspect}"
          expect_rewrite_record(row)
          next unless expected[:status] == 302

          location = last_response.headers['Location'].to_s
          if expected[:idp]
            entra_tenant = expected[:idp] == :tenant ? test_sso_config.tenant_id : 'placeholder'
            expect(location).to start_with("https://login.microsoftonline.com/#{entra_tenant}/")
          else
            expect(location).to end_with(expected[:location])
          end
        end
      end
    end
  end
end
