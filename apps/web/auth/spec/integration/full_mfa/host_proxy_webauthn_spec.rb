# apps/web/auth/spec/integration/full_mfa/host_proxy_webauthn_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack, MFA lane) — host and proxy
# simulation matrix, a live WebAuthn ceremony (#4223)
# =============================================================================
#
# host_proxy_matrix_spec.rb pins the INPUT of the ceremony for every shape:
# Auth::PublicHost.webauthn_host. This file runs the ceremony itself for the
# shapes a browser can be on, with a software authenticator (the webauthn
# gem's FakeClient) that signs real challenges for a real origin and RP ID:
#
#   rp_id   the RP ID the server offers at registration, and stores
#   origin  the origin the browser is on. The assertion is signed for it and
#           the server verifies it against config/features/webauthn.rb's
#           webauthn_origin, so a wrong value here fails the ceremony.
#
# Each row registers a passkey and then signs in with password plus passkey,
# both on the row's shape. The examples after the table cross two shapes.
#
# The RP ID and origin come from Auth::PublicHost, which does not read
# Rack's host, so the rows have the same outcome with public_host_rewrite
# off and on. `rewritten: {}` only records that the request is rewritten.
#
# A request that classified :invalid never reaches a ceremony: sign-in is
# refused on such a host (404), and a session signed in on a served host is
# refused there by the session evaluator (surface_mismatch, 401). The last
# three examples pin that, so the request-host fallback of webauthn_rp_id
# (config/features/webauthn.rb) stays unreachable (#4223 remaining scope 3).
#
# RUN:
#   tests/lanes/run full-mfa --only \
#     apps/web/auth/spec/integration/full_mfa/host_proxy_webauthn_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/webauthn_flow_helper'
require_relative '../../support/host_proxy_matrix_support'

module HostProxyMatrix
  WEBAUTHN_ROWS = [
    shape(:canonical_host, id: 'W01', case: 'canonical host',
      rp_id: '{canonical}', origin: CANONICAL_ORIGIN),
    shape(:canonical_port, id: 'W02', case: 'canonical host with a non-default port',
      rp_id: '{canonical}', origin: 'https://{canonical}:8443'),
    shape(:doubled_canonical, id: 'W03', case: 'doubled canonical Host',
      rp_id: '{canonical}', origin: CANONICAL_ORIGIN),
    shape(:tenant_host, id: 'W04', case: 'verified custom domain in Host',
      rp_id: '{tenant}', origin: TENANT_ORIGIN),
    shape(:tenant_forwarded, id: 'W05', case: 'tenant in X-Forwarded-Host',
      rp_id: '{tenant}', origin: TENANT_ORIGIN),
    shape(:tenant_forwarded_port, id: 'W06', case: 'tenant and a public port in X-Forwarded-Host',
      rp_id: '{tenant}', origin: 'https://{tenant}:8443'),
    shape(:doubled_tenant, id: 'W07', case: 'doubled verified custom domain Host',
      rp_id: '{tenant}', origin: TENANT_ORIGIN),
  ].freeze
end

# :full_auth_mode is what the integration/full/ directory gives its files
# and this one has to ask for: the auth configuration the one-shot boot
# reads, with the passkey feature the lane turns on.
RSpec.describe 'Host and proxy simulation matrix: WebAuthn ceremony (#4223)',
  :full_auth_mode, :shared_db_state, type: :integration do
  include_context 'host proxy rows'
  include WebauthnFlowHelper

  # Stop sending a row's headers, so the next shape starts clean.
  def clear_topology(row)
    row[:headers].each_key { |name| header name, nil }
    header 'X-Forwarded-Proto', nil
  end

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'
      include_context 'domains enabled'

      let(:matrix_canonical_host) { canonical_host }
      let(:account_email) { unique_test_email('matrix-passkey') }
      let!(:account_id) { seed_account_with_password(account_email) }

      # A member of the tenant's organization, on a tenant that allows
      # password sign-in, so the same account can sign in on both surfaces.
      before do
        customer = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
        Onetime::OrganizationMembership.ensure_membership(
          test_organization, customer, role: 'member', domain_scope_id: test_custom_domain.objid,
        )
        Onetime::CustomDomain::SigninConfig.create!(
          domain_id: test_custom_domain.identifier,
          enabled: true,
          signin_enabled: true,
          sso_enabled: true,
        )
      end

      after do
        Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
        clear_auth_database
      end

      def stored_rp_ids
        auth_db[:account_webauthn_keys].where(account_id: account_id).select_map(:rp_id)
      end

      HostProxyMatrix::WEBAUTHN_ROWS.each do |row|
        it HostProxyMatrix.row_name(row) do
          apply_topology(row)

          passkey = register_passkey_as_sent(email: account_email, rp_id: fill(row[:rp_id]), origin: fill(row[:origin]))
          expect(stored_rp_ids).to eq([fill(row[:rp_id])])

          login_with_password_and_passkey_as_sent(email: account_email, passkey: passkey)
          expect_rewrite_record(row)
        end
      end

      it 'accepts a passkey registered behind the Host-rewriting proxy when the proxy preserves Host' do
        forwarded = HostProxyMatrix.shape(:tenant_forwarded)
        preserved = HostProxyMatrix.shape(:tenant_host)

        apply_topology(forwarded)
        passkey = register_passkey_as_sent(
          email: account_email, rp_id: tenant_domain, origin: fill(HostProxyMatrix::TENANT_ORIGIN),
        )

        clear_topology(forwarded)
        apply_topology(preserved)
        login_with_password_and_passkey_as_sent(email: account_email, passkey: passkey)
      end

      # The browser is on the tenant. An assertion made on the origin target
      # (the Host the proxy sent) is for another origin and must not verify,
      # with the rewrite on as well as off.
      it 'refuses an assertion signed for the origin target on a tenant request' do
        row           = HostProxyMatrix.shape(:tenant_forwarded)
        authenticator = WebAuthn::FakeAuthenticator.new

        apply_topology(row)
        passkey = register_passkey_as_sent(
          email: account_email, rp_id: tenant_domain, origin: fill(HostProxyMatrix::TENANT_ORIGIN),
          authenticator: authenticator,
        )

        elsewhere = WebauthnFlowHelper::Passkey.new(
          client: WebAuthn::FakeClient.new(fill(HostProxyMatrix::CANONICAL_ORIGIN), authenticator: authenticator),
          origin: fill(HostProxyMatrix::CANONICAL_ORIGIN),
          rp_id: passkey.rp_id,
          webauthn_id: passkey.webauthn_id,
        )
        login_with_password_and_passkey_as_sent(email: account_email, passkey: elsewhere, expected_status: 422)
      end

      it 'refuses sign-in on an unregistered host, so no ceremony reads the request-host fallback' do
        apply_topology(HostProxyMatrix.shape(:unregistered_host))

        csrf_json_post('/auth/login', login: account_email, password: AuthTestConstants::TEST_PASSWORD)

        expect(last_request.env['onetime.domain_strategy']).to eq(:invalid)
        expect(Auth::PublicHost.webauthn_host(last_request.env)).to be_nil
        expect(last_response.status).to eq(404)
      end

      # The RP ID on a request that classified :invalid (#4223 remaining
      # scope 3). Auth::PublicHost declines such a request and
      # config/features/webauthn.rb would fall back to Rack's own authority:
      # 'localhost' for H07, nil for D04 (an authority Rack cannot parse).
      # Neither value is ever offered. Sign-in is refused on such a host (the
      # example above), and a session signed in on a served host is refused
      # there by Onetime::Session::CustomerSessionEvaluator (surface_mismatch)
      # before Rodauth runs, so no registration or assertion ceremony starts
      # on an :invalid request. These pin the refusal and the fallback value
      # it keeps unreachable.
      describe 'a request that classified :invalid' do
        def sign_in_on_canonical
          apply_topology(HostProxyMatrix.shape(:canonical_host))
          csrf_json_post('/auth/login', login: account_email, password: AuthTestConstants::TEST_PASSWORD)
          expect(last_response.status).to eq(200),
            "Precondition failed: sign-in (#{last_response.status}: #{last_response.body})"
          clear_topology(HostProxyMatrix.shape(:canonical_host))
        end

        it 'refuses the registration ceremony on localhost (H07), where the fallback would be Rack\'s host' do
          sign_in_on_canonical
          apply_topology(HostProxyMatrix.shape(:localhost))

          csrf_json_post('/auth/webauthn-setup', password: AuthTestConstants::TEST_PASSWORD)

          expect(last_request.env['onetime.domain_strategy']).to eq(:invalid)
          expect(Auth::PublicHost.webauthn_host(last_request.env)).to be_nil
          expect(Rack::Request.new(last_request.env).host).to eq('localhost')
          expect(last_response.status).to eq(401)
          expect(stored_rp_ids).to eq([])
        end

        it 'refuses the registration ceremony on a doubled IP-literal Host (D04), where the fallback would be nil' do
          sign_in_on_canonical
          apply_topology(HostProxyMatrix.shape(:doubled_site_host))

          csrf_json_post('/auth/webauthn-setup', password: AuthTestConstants::TEST_PASSWORD)

          expect(last_request.env['onetime.domain_strategy']).to eq(:invalid)
          expect(Auth::PublicHost.webauthn_host(last_request.env)).to be_nil
          expect(Rack::Request.new(last_request.env).host).to be_nil
          expect(last_response.status).to eq(401)
          expect(stored_rp_ids).to eq([])
        end
      end
    end
  end
end
