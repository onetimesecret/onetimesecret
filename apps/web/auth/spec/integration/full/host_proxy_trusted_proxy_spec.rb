# apps/web/auth/spec/integration/full/host_proxy_trusted_proxy_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack) — host and proxy simulation matrix,
# with site.network.trusted_proxy configured (#4223)
# =============================================================================
#
# host_proxy_matrix_spec.rb runs with no trusted-proxy configuration, which
# is the default: Rack::DetectHost then trusts a private or loopback peer by
# heuristic. An install behind a CDN or a load balancer configures trust,
# and the decision moves to otto's IPPrivacyMiddleware, which writes
# env['otto.via_trusted_proxy'] for DetectHost and StripForwardedHost to
# read. Other specs set that key by hand. Here it is otto that sets it, from
# real configuration, for both modes:
#
#   filter  a peer is trusted when its address is private or loopback
#           (MiddlewareStack::PRIVATE_PROXY_RANGES, always in the set) or
#           inside site.network.trusted_proxy.cidrs
#   depth   every connecting peer is trusted. The mode counts hops in
#           X-Forwarded-For and assumes the application is reachable only
#           through the proxy chain, so a forwarded host from a public
#           address is honoured (rows TD01, TD04).
#
# Trust is compiled into each application's middleware stack when the
# application is built, and the stack the other matrix files use was built
# without it. So each example builds the auth application again under the
# configuration it names and sends the row through that.
#
# `trusted` is what otto records for the connecting peer. The other keys
# are the request matrix's (see host_proxy_matrix_spec.rb), with
# `rewritten:` naming what differs with public_host_rewrite on.
#
# THIS FILE PINS CURRENT BEHAVIOUR.
#
# RUN:
#   tests/lanes/run full-sqlite --only \
#     apps/web/auth/spec/integration/full/host_proxy_trusted_proxy_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/host_proxy_matrix_support'

module HostProxyMatrix
  # --- filter mode, cidrs: [TRUSTED_PEER_CIDR] --------------------------------
  TRUSTED_FILTER_ROWS = [
    { id: 'TF01', case: 'tenant in X-Forwarded-Host from a listed public peer',
      peer: :trusted_public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      trusted: true, rack_host: '{canonical}', **TENANT,
      rewritten: { rack_host: '{tenant}' } },
    # Not in the list: its forwarded host and its X-Forwarded-Proto are
    # dropped, as with no configuration (matrix row U01).
    { id: 'TF02', case: 'tenant in X-Forwarded-Host from an unlisted public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      trusted: false, **CANONICAL, origin: 'http://{canonical}', rack_base_url: 'http://{canonical}' },
    # Private and loopback addresses are always in the filter-mode set.
    { id: 'TF03', case: 'tenant in X-Forwarded-Host from a loopback peer',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      trusted: true, rack_host: '{canonical}', **TENANT,
      rewritten: { rack_host: '{tenant}' } },
    { id: 'TF04', case: 'canonical host from a listed public peer',
      peer: :trusted_public, headers: { 'Host' => '{canonical}' },
      trusted: true, **CANONICAL },
    { id: 'TF05', case: 'verified custom domain in Host from an unlisted public peer',
      peer: :public, headers: { 'Host' => '{tenant}' },
      trusted: false, rack_host: '{tenant}', **TENANT, origin: 'http://{tenant}', rack_base_url: 'http://{tenant}' },
    { id: 'TF06', case: 'Forwarded host= names the tenant, from a listed public peer',
      peer: :trusted_public,
      headers: { 'Host' => '{canonical}', 'Forwarded' => 'for=198.51.100.1;host={tenant};proto=https' },
      trusted: true, **CANONICAL },
    { id: 'TF07', case: 'bare X-Forwarded-Host with the public port in X-Forwarded-Port, from a listed public peer',
      peer: :trusted_public,
      headers: { 'Host' => '{canonical}:3000', 'X-Forwarded-Host' => '{tenant}', 'X-Forwarded-Port' => '8443' },
      trusted: true, rack_host: '{canonical}', **TENANT, origin: 'https://{tenant}:3000',
      rewritten: { rack_host: '{tenant}', origin: 'https://{tenant}:8443', rack_base_url: 'https://{tenant}:8443' } },
    { id: 'TF08', case: 'unregistered host in X-Forwarded-Host from a listed public peer',
      peer: :trusted_public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => UNREGISTERED },
      trusted: true, rack_host: '{canonical}', detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'TF09', case: 'comma-joined X-Forwarded-Host from a listed public peer falls to Host',
      peer: :trusted_public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => "{tenant}, #{UNREGISTERED}" },
      trusted: true, **CANONICAL },
    { id: 'TF10', case: 'Apx-Incoming-Host from a listed public peer is not read',
      peer: :trusted_public, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      trusted: true, **CANONICAL },
  ].freeze

  # --- depth mode, depth: 1 ---------------------------------------------------
  TRUSTED_DEPTH_ROWS = [
    { id: 'TD01', case: 'tenant in X-Forwarded-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      trusted: true, rack_host: '{canonical}', **TENANT,
      rewritten: { rack_host: '{tenant}' } },
    { id: 'TD02', case: 'tenant in X-Forwarded-Host from a loopback peer',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      trusted: true, rack_host: '{canonical}', **TENANT,
      rewritten: { rack_host: '{tenant}' } },
    { id: 'TD03', case: 'canonical host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}' },
      trusted: true, **CANONICAL },
    # The peer's X-Forwarded-Proto is kept, unlike matrix row U05.
    { id: 'TD04', case: 'verified custom domain in Host from a public peer',
      peer: :public, headers: { 'Host' => '{tenant}' },
      trusted: true, rack_host: '{tenant}', **TENANT },
    { id: 'TD05', case: 'Forwarded host= names the tenant, from a public peer',
      peer: :public,
      headers: { 'Host' => '{canonical}', 'Forwarded' => 'for=198.51.100.1;host={tenant};proto=https' },
      trusted: true, **CANONICAL },
    { id: 'TD06', case: 'unregistered host in X-Forwarded-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => UNREGISTERED },
      trusted: true, rack_host: '{canonical}', detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
  ].freeze

  TRUSTED_PROXY_MODES = {
    'filter' => { config: { 'enabled' => true, 'mode' => 'filter', 'cidrs' => [TRUSTED_PEER_CIDR] },
                  rows: TRUSTED_FILTER_ROWS },
    'depth' => { config: { 'enabled' => true, 'mode' => 'depth', 'depth' => 1 },
                 rows: TRUSTED_DEPTH_ROWS },
  }.freeze
end

RSpec.describe 'Host and proxy simulation matrix: configured trusted proxy (#4223)',
  :shared_db_state, type: :integration do
  include_context 'host proxy rows'

  # The auth application, built under the configuration the example set.
  # Rack::Test asks for `app` at the first request, after every `before`.
  def app
    @trusted_proxy_app ||= Rack::URLMap.new('/auth' => Auth::Application.new)
  end

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'
      include_context 'domains enabled'

      let(:matrix_canonical_host) { canonical_host }

      HostProxyMatrix::TRUSTED_PROXY_MODES.each do |mode, spec|
        context "with trusted_proxy.mode #{mode}" do
          before do
            network                  = (OT.conf['site']['network'] ||= {})
            @trusted_proxy_had_key   = network.key?('trusted_proxy')
            @trusted_proxy_saved     = network['trusted_proxy']
            network['trusted_proxy'] = spec[:config].dup
          end

          after do
            network = OT.conf['site']['network']
            if @trusted_proxy_had_key
              network['trusted_proxy'] = @trusted_proxy_saved
            else
              network.delete('trusted_proxy')
            end
          end

          it 'compiles the configured mode into the application it builds' do
            config = Onetime::Application::MiddlewareStack.ip_privacy_security_config

            expect(config.proxy_trust_configured?).to be(true)
            expect(config.trusted_proxy_depth_mode?).to eq(mode == 'depth')
          end

          spec[:rows].each do |row|
            it HostProxyMatrix.row_name(row) do
              prepare_record(row[:record])
              apply_topology(row)
              header 'Accept', 'application/json'
              get '/auth'

              expect(last_request.env['otto.via_trusted_proxy']).to eq(row[:trusted])
              expect_observed(row)
            end
          end
        end
      end
    end
  end
end
