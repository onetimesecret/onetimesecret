# apps/web/auth/spec/support/host_proxy_matrix_support.rb
#
# frozen_string_literal: true

# =============================================================================
# Host and proxy simulation matrix (#4223): the request shapes and the
# helpers that send them, shared by the matrix files.
#
# integration/full/host_proxy_matrix_spec.rb holds the request and emitter
# tables and the topology probe. The sibling files (host_proxy_document_spec,
# host_proxy_origin_spec, host_proxy_link_emitters_spec) drive other emitters
# through the same shapes. Everything they have in common is here, so a
# shape means the same thing in every file:
#
#   {tenant}     the verified custom domain of the 'tenant fixtures' context
#   {canonical}  features.domains.default (`matrix_canonical_host`, which the
#                including group defines)
#
# A row is a Hash. The keys every file reads:
#
#   id, case     the example name
#   headers      request headers, with the placeholders above
#   peer         :public sends the request from a public address, and
#                :trusted_public from one inside the CIDR list the
#                trusted-proxy rows configure; by default it comes from
#                loopback, which DetectHost's legacy heuristic trusts when no
#                proxy trust is configured
#   proto        nil sends no X-Forwarded-Proto; otherwise https is sent
#   record       :unverified or :read_fails puts the tenant's CustomDomain
#                record in that state; nil leaves it verified
#   site_host    replaces site.host for the example; nil unsets it
#   rewritten    the values that differ with public_host_rewrite on; its
#                presence says the request is rewritten
#   changes_with the issue expected to change the row's outcome
#
# The including group defines `matrix_canonical_host` and `rewrite_on`.
# =============================================================================

require_relative 'tenant_test_fixtures'
require_relative 'domains_enabled_context'
require_relative 'public_host_rewrite_context'
require 'rack/test'

module HostProxyMatrix
  # A host with no CustomDomain record, on a registrable domain that is not
  # a peer of any canonical host used below.
  UNREGISTERED = 'unregistered.tenant-example.com'

  # A public address for the connecting peer. With no trusted-proxy
  # configuration (the default, and the test configuration) DetectHost
  # honours forwarded host headers from a private or loopback peer only.
  PUBLIC_PEER = '203.0.113.7'

  # A public address inside the CIDR list the trusted-proxy rows configure
  # (host_proxy_trusted_proxy_spec.rb). Not trusted anywhere else.
  TRUSTED_PEER      = '198.51.100.10'
  TRUSTED_PEER_CIDR = '198.51.100.0/24'

  # What a request row observes after the stack ran. See the header of
  # integration/full/host_proxy_matrix_spec.rb for each key.
  OBSERVED_KEYS = [:rack_host, :detected, :display, :strategy, :origin, :tenant_host, :webauthn_host].freeze

  TENANT_ORIGIN    = 'https://{tenant}'
  CANONICAL_ORIGIN = 'https://{canonical}'

  # site.host in spec/config.test.yaml. An IP literal: DetectHost never
  # accepts it, and with the domains feature on it is not a parseable member
  # of the canonical set.
  SITE_HOST        = '127.0.0.1:3000'
  SITE_HOST_ORIGIN = 'https://127.0.0.1:3000'

  # What a request served as the tenant's verified custom domain produces.
  TENANT = {
    detected: '{tenant}',
    display: '{tenant}',
    strategy: :custom,
    origin: TENANT_ORIGIN,
    tenant_host: '{tenant}',
    webauthn_host: '{tenant}',
  }.freeze

  # What a request served as features.domains.default produces.
  CANONICAL = {
    rack_host: '{canonical}',
    detected: '{canonical}',
    display: '{canonical}',
    strategy: :canonical,
    origin: CANONICAL_ORIGIN,
    tenant_host: nil,
    webauthn_host: '{canonical}',
  }.freeze

  # Domains feature off: DomainStrategy classifies nothing, every request is
  # :canonical and display_domain is site.host as configured, port included.
  OFF = {
    detected: nil,
    display: SITE_HOST,
    strategy: :canonical,
    origin: "http://#{SITE_HOST}",
    tenant_host: nil,
    webauthn_host: nil,
  }.freeze

  # The shapes the emitter files share. Each is the request half of a row;
  # the file adds the outcome keys its emitter produces.
  SHAPES = {
    canonical_host:        { headers: { 'Host' => '{canonical}' } },
    tenant_host:           { headers: { 'Host' => '{tenant}' } },
    tenant_forwarded:      { headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' }, rewritten: {} },
    tenant_forwarded_port: { headers: { 'Host' => '{canonical}:8443', 'X-Forwarded-Host' => '{tenant}:8443' },
                             rewritten: {} },
    canonical_port:        { headers: { 'Host' => '{canonical}:8443' } },
    doubled_canonical:     { headers: { 'Host' => '{canonical}, {canonical}' }, rewritten: {} },
    doubled_tenant:        { headers: { 'Host' => '{tenant}, {tenant}' }, rewritten: {} },
    unregistered_host:     { headers: { 'Host' => UNREGISTERED } },
    unregistered_forwarded: { headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => UNREGISTERED } },
    forwarded_public_peer: { peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' } },
    rfc7239_tenant:        { headers: { 'Host' => '{canonical}',
                                        'Forwarded' => 'for=198.51.100.1;host={tenant};proto=https' } },
    unverified_forwarded:  { record: :unverified,
                             headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' }, rewritten: {} },
    read_fails_forwarded:  { record: :read_fails, changes_with: '#4220',
                             headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' } },
  }.freeze

  # A row built from a shared shape: `shape(:tenant_forwarded, id: 'X01',
  # case: '...', link: ...)`. The outcome keys given here win over the
  # shape's own (a file may say a shape is not rewritten for its emitter).
  def self.shape(name, **outcome)
    SHAPES.fetch(name).merge(outcome)
  end

  # The example name a row produces.
  def self.row_name(row)
    suffix = row[:changes_with] ? " (current behaviour; #{row[:changes_with]})" : ''
    "#{row[:id]} #{row[:case]}#{suffix}"
  end
end

RSpec.shared_context 'host proxy rows' do
  include Rack::Test::Methods

  # :shared_db_state for the reason tenant_sso_proxy_host_spec.rb gives: the
  # fixtures come from this context's `let!` hooks and the per-example flush
  # can land after them. Each example builds under a unique run id and tears
  # down in `after`.
  include_context 'tenant fixtures'

  before(:all) { boot_onetime_app }

  # The stack pins Rack's forwarded-header family when it is built
  # (MiddlewareStack.ip_privacy_security_config). spec/spec_helper.rb resets
  # that pin after every example while the mounted stack stays memoized, so
  # without this every example after the first in a process would run with
  # Rack's default family, which a deployment never has. Re-apply it the way
  # the stack build does.
  before { Onetime::Application::MiddlewareStack.ip_privacy_security_config }

  # Every row needs SSO on at boot, not only the emitter rows: the request
  # rows read their origin through OmniAuth's full_host resolver, which is
  # installed with the SSO feature. Stated once here so a lane without the
  # flag (full-pg) reports the precondition instead of a nil resolver.
  before do
    expect(Onetime.auth_config.orgs_sso_enabled?).to be(true),
      'HP-PRE-01: this matrix requires ORGS_SSO_ENABLED=true at boot. ' \
      'Run tests/lanes/run full-sqlite --only ' \
      "#{RSpec.current_example.metadata[:file_path].delete_prefix('./')} " \
      '(or full-pg-agnostic for Postgres); shell exports are scrubbed by the runner.'
  end

  # Replace the row's placeholders with this example's hosts.
  def fill(value)
    return value unless value.is_a?(String)

    value.gsub('{tenant}', tenant_domain).gsub('{canonical}', matrix_canonical_host)
  end

  # Put the tenant's CustomDomain record in the state the row names.
  def prepare_record(state)
    case state
    when :unverified
      test_custom_domain.verified = false
      test_custom_domain.save
    when :read_fails
      # The index read every display-domain loader starts with, so the
      # middleware, Auth::PublicHost and the tenant hook all see the failure.
      allow(Onetime::CustomDomain).to receive(:display_domain_id_for)
        .and_raise(Redis::BaseError.new('simulated read failure'))
    end
  end

  # Run the block with site.host replaced, when the row asks for it.
  # DomainStrategy derives its canonical set from OT.conf at
  # initialize_from_config, so both are updated and both are put back.
  def with_site_host(host = :unchanged)
    return yield if host == :unchanged

    saved = OT.conf['site']['host']
    begin
      OT.conf['site']['host'] = fill(host)
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
      yield
    ensure
      OT.conf['site']['host'] = saved
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
    end
  end

  # Apply the row's connecting peer and headers to every later request of
  # this example.
  def apply_topology(row)
    env 'REMOTE_ADDR', HostProxyMatrix::PUBLIC_PEER if row[:peer] == :public
    env 'REMOTE_ADDR', HostProxyMatrix::TRUSTED_PEER if row[:peer] == :trusted_public
    header 'X-Forwarded-Proto', 'https' unless row.key?(:proto) && row[:proto].nil?
    row[:headers].each { |name, value| header name, fill(value) }
  end

  # The row as it reads for this run: with the rewrite on, the row's
  # `rewritten:` values replace the ones they name.
  def row_for_run(row)
    rewrite_on ? row.merge(row.fetch(:rewritten, {})) : row
  end

  # What the rewrite did to the request, in both runs: whether it rewrote,
  # and that the Host as sent is still readable.
  def expect_rewrite_record(row, env: last_request.env)
    expect(env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST))
      .to eq(rewrite_on && row.key?(:rewritten))
    expect(Onetime::Middleware::PublicHostRewrite.original_http_host(env)).to eq(fill(row[:headers]['Host']))
  end

  # What the stack left in the env of the last request, and what the two
  # auth-URL readers build on it.
  def observed
    env     = last_request.env
    request = Rack::Request.new(env)
    {
      rack_host: request.host,
      rack_base_url: request.base_url,
      detected: env[Rack::DetectHost.result_field_name],
      display: env['onetime.display_domain'],
      strategy: env['onetime.domain_strategy'],
      origin: OmniAuth.config.full_host.call(env),
      email_origin: Auth::PublicHost.allowlisted_base_url(env),
      tenant_host: Auth::Config::Features::OmniAuth.public_host_for(env),
      webauthn_host: Auth::PublicHost.webauthn_host(env),
    }
  end

  # The request matrix's assertions for one row, after its request was sent.
  def expect_observed(row)
    actual   = observed
    expects  = row_for_run(row)
    expected = HostProxyMatrix::OBSERVED_KEYS.to_h { |key| [key, fill(expects[key])] }

    expect(actual.slice(*HostProxyMatrix::OBSERVED_KEYS)).to eq(expected)
    expect_rewrite_record(row)
    # The redirect_uri and the emailed link read one chain.
    expect(actual[:email_origin]).to eq(actual[:origin])
    expect(actual[:rack_base_url]).to eq(fill(expects[:rack_base_url])) if expects.key?(:rack_base_url)
    # Whatever the row sent, no auth URL carries a comma.
    expect(actual[:origin]).not_to include(',')
  end

  # scheme://host, with the port only when it is not the scheme default.
  def origin_of(url)
    uri     = URI.parse(url)
    default = uri.scheme == 'https' ? 443 : 80
    uri.port == default ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
