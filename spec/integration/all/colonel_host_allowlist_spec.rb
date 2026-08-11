# spec/integration/all/colonel_host_allowlist_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, real middleware stack, real Valkey)
# =============================================================================
#
# #4062: the Colonel admin surfaces (/colonel shell + /api/colonel API) are
# bound to an explicit HOST allowlist, enforced by
# Onetime::Middleware::AdminNetworkIsolation. A request whose detected host is
# not on the list gets a 404 — indistinguishable-from-absent, for authenticated
# colonels and anonymous callers alike.
#
# These are FULL-STACK request specs: the app under test is the real
# Rack::URLMap the server boots, so AdminNetworkIsolation is exercised in its
# real position (below Rack::DetectHost, above Onetime::Session and
# DomainStrategy) with a real detected host derived from the Host header.
#
# Mode-agnostic on purpose. The gate reads config and the detected host only —
# nothing in it varies with AUTHENTICATION_MODE — and the assertions below are
# written against behaviour that is identical in every mode. Running it in
# every lane is the point: it is the same guard in all of them.
#
# WHY EVERY DENIAL CASE HAS A GATE-OFF CONTROL
#
# A 404 is a weak signal on its own — an unmatched route produces one too. Each
# denial group is therefore paired with the SAME request against a stack built
# with the `*` escape hatch, which must produce the ordinary served response.
# If the gate were deleted the controls would stay green and the denials would
# go red.
#
# TWO PIECES OF STATE ARE RESOLVED AT CONSTRUCTION, NOT PER REQUEST
#
#   1. AdminNetworkIsolation resolves both allowlists in #initialize, and
#      DomainStrategy loads its class state there too. Writing OT.conf after
#      the Rack app is built has no effect: `configure_admin!` drops the
#      memoized app so the next request builds a stack that read the new config.
#   2. The custom-domains FEATURE flag is not read from OT.conf at request time
#      at all — DomainStrategy#call asks Onetime::Runtime.features.domains?,
#      which the ConfigureDomains initializer sets once at boot. Flipping
#      OT.conf['features']['domains']['enabled'] alone leaves the whole
#      override/classification branch dead, which silently turns the
#      O-Domain-Context spoofing tests below into assertions about nothing.
#      configure_admin! therefore writes Runtime state too, and restores it.
#
# RUN (mode-agnostic — runs in every mode lane):
#   tests/lanes/run simple
#   tests/lanes/run full-sqlite
#   tests/lanes/run disabled
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'

RSpec.describe 'Colonel admin surface host allowlist (#4062)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Without this, Rack::URLMap has no /api/* entries and every API request
    # 404s at the map level — which would look exactly like a host denial and
    # pass vacuously.
    Onetime::Application::Registry.prepare_application_registry
  end

  # Restore every piece of state these examples write. DomainStrategy caches its
  # own class state from the same config at app-construction time, so the final
  # restore also rebuilds one stack: that re-runs initialize_from_config
  # against the pristine config and leaves no cross-file residue.
  before do
    @orig_admin      = OT.conf.dig('site', 'admin')&.dup
    @orig_site_host  = OT.conf.dig('site', 'host')
    @orig_domains    = OT.conf.dig('features', 'domains')&.dup
    @orig_developmnt = OT.conf['development']&.dup
    @orig_features   = Onetime::Runtime.features
  end

  after do
    OT.conf['site']['admin']        = @orig_admin if @orig_admin
    OT.conf['site']['host']         = @orig_site_host
    OT.conf['features']['domains']  = @orig_domains if @orig_domains
    OT.conf['development']          = @orig_developmnt if @orig_developmnt
    Onetime::Runtime.features       = @orig_features
    Onetime::Application::Registry.generate_rack_url_map
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  # Write every input the two gates and DomainStrategy read, then drop the
  # memoized app. Defaults describe a stock canonical deployment with the
  # allowlist unset, i.e. the anchor fallback.
  def configure_admin!(allowed_hosts: [], allowed_cidrs: [], site_host: 'example.com',
                       default_domain: 'example.com', link_domains: nil,
                       domains_enabled: false, domain_context: false)
    OT.conf['site']['admin'] = {
      'allowed_hosts' => allowed_hosts,
      'allowed_cidrs' => allowed_cidrs,
    }
    OT.conf['site']['host'] = site_host

    domains                 = (OT.conf['features']['domains'] || {}).dup
    domains['enabled']      = domains_enabled
    domains['default']      = default_domain
    domains['link_domains'] = link_domains
    OT.conf['features']['domains'] = domains

    development = (OT.conf['development'] || {}).dup
    development['domain_context_enabled'] = domain_context
    OT.conf['development'] = development

    # The request path reads the FEATURE flag from Runtime, not OT.conf. See
    # the header note; without this the domains branch never executes.
    Onetime::Runtime.update_features(domains_enabled: domains_enabled)

    @app = nil
    reset_rack_test_session!
  end

  # Rack::Test::Methods memoizes a Session around the app the FIRST time a
  # request is made in an example, so dropping @app alone is not enough to
  # reconfigure MID-example: the session would keep serving the old stack and
  # the new config would silently never apply. Drop the memo too.
  def reset_rack_test_session!
    @_rack_test_sessions        = nil
    @_rack_test_current_session = nil
  end

  # A route on the SAME stack that the admin gate must never touch. Used as the
  # "this vhost is reachable, it is the admin surface specifically that is
  # absent" control; it is public, so it needs no session.
  NON_ADMIN_PATH = '/api/v2/status'

  # ---------------------------------------------------------------------------
  # Principals. Real Customer records, so the role gates beneath the middleware
  # are the real ones. Created inside the example (type: :integration flushes
  # Valkey before each).
  # ---------------------------------------------------------------------------
  def create_customer(role:)
    cust          = Onetime::Customer.create!(email: "#{role}-#{SecureRandom.hex(4)}@example.com")
    cust.role     = role
    cust.verified = 'true'
    cust.save
    cust
  end

  let(:colonel) { create_customer(role: 'colonel') }
  let(:regular) { create_customer(role: 'customer') }

  # Otto's session auth strategy reads env['rack.session']; injecting the hash
  # is the established pattern here (spec/integration/full/admin_interface_spec.rb).
  def signed_in_as(user)
    env 'rack.session', {
      'external_id' => user.extid,
      'authenticated' => true,
      'session_id' => SecureRandom.hex(16),
    }
  end

  def anonymous!
    env 'rack.session', nil
    clear_cookies
  end

  # ---------------------------------------------------------------------------
  # Requests. `Host:` is what Rack::DetectHost validates into
  # env['rack.detected_host'], which is the only host input the gate reads.
  # ---------------------------------------------------------------------------
  def get_shell(host, rack_env = {})
    header 'Host', host
    header 'Accept', 'text/html'
    get '/colonel', {}, rack_env
  end

  def get_api(host, rack_env = {})
    header 'Host', host
    header 'Accept', 'application/json'
    get '/api/colonel/info', {}, rack_env
  end

  # The gate's HTML body, distinct from the SPA shell the real /colonel serves.
  def gate_html_denial?
    last_response.status == 404 &&
      last_response.headers['content-type'] == 'text/html; charset=utf-8' &&
      last_response.body.include?('404 Not Found')
  end

  def json_body
    JSON.parse(last_response.body)
  end

  # Capture the gate's log lines as [message, payload] pairs. The middleware
  # resolves its logger ONCE, at construction — the first request after
  # configure_admin! drops the memoized app is what constructs it — so this
  # must be installed before that request. The sink is a plain object rather
  # than a double: the stack built inside an example can outlive the example's
  # mock scope. Every other logger passes through untouched.
  def capture_admin_gate_warns!
    warns = []
    sink  = Object.new
    sink.define_singleton_method(:warn) { |message, payload = {}| warns << [message, payload] }
    %i[info error debug].each { |level| sink.define_singleton_method(level) { |*, **| } }
    allow(Onetime).to receive(:get_logger).and_wrap_original do |original, name|
      name == 'AdminNetworkIsolation' ? sink : original.call(name)
    end
    warns
  end

  # A real verified tenant domain owned by `owner`. The host gate does not
  # consult CustomDomain rows — it judges the detected host alone — but the AC
  # names this case, and a real row is what makes the gate-off control an
  # honest statement about a domain the deployment genuinely serves.
  def create_verified_custom_domain(owner, fqdn)
    org             = Onetime::Organization.create!("Tenant #{SecureRandom.hex(4)}", owner)
    domain          = Onetime::CustomDomain.create!(fqdn, org.objid)
    domain.verified = 'true'
    domain.save
    domain
  end

  # ===========================================================================
  # 1. Default config (allowed_hosts unset) — canonical anchors only
  # ===========================================================================
  describe 'with allowed_hosts unset (canonical anchor fallback)' do
    before { configure_admin!(default_domain: 'example.com', site_host: 'example.com') }

    context 'on the canonical host' do
      it 'serves the shell to a colonel, exactly as before #4062' do
        signed_in_as(colonel)
        get_shell('example.com')

        expect(last_response.status).to eq(200)
        expect(last_response.headers['content-type']).to match(%r{text/html})
        expect(last_response.body).to include('<!doctype html')
      end

      it 'serves the API to a colonel' do
        signed_in_as(colonel)
        get_api('example.com')

        expect(last_response.status).to eq(200)
        expect(json_body).to have_key('details')
      end

      # The role gates beneath the middleware are untouched: an unauthorized
      # caller on an ALLOWLISTED host must still be refused BY THEM (a redirect
      # or a 401/403), never by the host gate's 404. This is the "behaviour is
      # exactly as today on an allowlisted host" half of the contract.
      it 'still refuses an anonymous caller at the ROLE gate, not the host gate' do
        anonymous!
        get_shell('example.com')

        expect(last_response.status).not_to eq(404)
        expect(gate_html_denial?).to be false
      end

      it 'still 401s an anonymous API caller at the role gate' do
        anonymous!
        get_api('example.com')

        expect(last_response.status).to eq(401)
      end

      it 'still 403s a non-colonel API caller at the role gate' do
        signed_in_as(regular)
        get_api('example.com')

        expect(last_response.status).to eq(403)
      end
    end

    context 'on the www. variant of the canonical host' do
      it 'serves the shell to a colonel' do
        signed_in_as(colonel)
        get_shell('www.example.com')

        expect(last_response.status).to eq(200)
      end

      it 'serves the API to a colonel' do
        signed_in_as(colonel)
        get_api('www.example.com')

        expect(last_response.status).to eq(200)
      end

      it 'keeps the role gate in place there too' do
        signed_in_as(regular)
        get_api('www.example.com')

        expect(last_response.status).to eq(403)
      end
    end

    context 'on a subdomain of the canonical host' do
      it '404s the shell for a colonel' do
        signed_in_as(colonel)
        get_shell('tenant.example.com')

        expect(gate_html_denial?).to be true
      end

      it '404s the API for a colonel' do
        signed_in_as(colonel)
        get_api('tenant.example.com')

        expect(last_response.status).to eq(404)
        expect(last_response.headers['content-type']).to eq('application/json')
        expect(json_body).to eq('error' => 'Not Found')
      end

      it '404s an anonymous caller too — no redirect, no 401' do
        anonymous!
        get_shell('tenant.example.com')
        expect(last_response.status).to eq(404)

        get_api('tenant.example.com')
        expect(last_response.status).to eq(404)
      end

      it '404s a non-colonel — the host gate answers before the role gate' do
        signed_in_as(regular)
        get_api('tenant.example.com')

        expect(last_response.status).to eq(404)
      end
    end

    context 'on an unrelated host' do
      it '404s both surfaces for a colonel' do
        signed_in_as(colonel)

        get_shell('unknown.example.org')
        expect(last_response.status).to eq(404)

        get_api('unknown.example.org')
        expect(last_response.status).to eq(404)
      end

      it '404s both surfaces for an anonymous caller' do
        anonymous!

        get_shell('unknown.example.org')
        expect(last_response.status).to eq(404)

        get_api('unknown.example.org')
        expect(last_response.status).to eq(404)
      end

      # Control: the SAME host with the gate off is served normally, so the
      # 404s above are the gate's doing and not a routing accident.
      it 'serves the same host once the gate is off (control)' do
        configure_admin!(allowed_hosts: ['*'], default_domain: 'example.com', site_host: 'example.com')
        signed_in_as(colonel)
        get_api('unknown.example.org')

        expect(last_response.status).to eq(200)
      end
    end

    # A /colonel or /api/colonel SUBPATH is gated identically; nothing about
    # the match depends on the exact endpoint.
    context 'on subpaths' do
      it 'gates /api/colonel/stats the same way' do
        signed_in_as(colonel)
        header 'Host', 'tenant.example.com'
        get '/api/colonel/stats'

        expect(last_response.status).to eq(404)
      end

      it 'leaves a NON-admin path untouched on a denied host' do
        anonymous!
        header 'Host', 'tenant.example.com'
        get NON_ADMIN_PATH

        expect(last_response.status).to eq(200)
      end
    end
  end

  # ===========================================================================
  # 2. A verified tenant custom domain, with the domains feature ON
  # ===========================================================================
  # The AC names this case specifically: features.domains.enabled = true and a
  # real verified CustomDomain row. DomainStrategy classifies that host
  # :custom, and the admin surfaces must still be absent on it.
  describe 'with features.domains.enabled and a verified custom domain' do
    let(:tenant_host) { 'secrets.tenant-example.com' }

    before do
      configure_admin!(
        default_domain: 'example.com',
        site_host: 'example.com',
        domains_enabled: true,
      )
      create_verified_custom_domain(colonel, tenant_host)
    end

    it '404s the shell on the tenant domain for a colonel' do
      signed_in_as(colonel)
      get_shell(tenant_host)

      expect(gate_html_denial?).to be true
    end

    it '404s the API on the tenant domain for a colonel' do
      signed_in_as(colonel)
      get_api(tenant_host)

      expect(last_response.status).to eq(404)
      expect(json_body).to eq('error' => 'Not Found')
    end

    it '404s the tenant domain for an anonymous caller' do
      anonymous!
      get_api(tenant_host)

      expect(last_response.status).to eq(404)
    end

    it 'still serves the canonical host, so the gate is active and not blanket-denying' do
      signed_in_as(colonel)
      get_api('example.com')

      expect(last_response.status).to eq(200)
    end

    # Control: the tenant host IS a host this deployment serves and classifies
    # :custom. Without this the 404s above could mean "that vhost reaches
    # nothing at all", which would be evidence about routing, not the gate.
    it 'serves the tenant domain — classified :custom — once the gate is off (control)' do
      configure_admin!(
        allowed_hosts: ['*'],
        default_domain: 'example.com',
        site_host: 'example.com',
        domains_enabled: true,
      )
      signed_in_as(colonel)
      get_api(tenant_host)

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('custom')
    end
  end

  # ===========================================================================
  # 3. A features.domains.link_domains pool member is NOT an admin host (#4063)
  # ===========================================================================
  describe 'with a link_domains pool configured' do
    before do
      configure_admin!(
        default_domain: 'example.com',
        site_host: 'example.com',
        link_domains: ['links.example.net'],
        domains_enabled: true,
      )
    end

    it 'classifies the pool member as canonical (the config really took)' do
      expect(Onetime::Utils::CanonicalHosts.normalized_hosts).to include('links.example.net')
    end

    it '404s the admin API on a link-pool domain' do
      signed_in_as(colonel)
      get_api('links.example.net')

      expect(last_response.status).to eq(404)
    end

    it '404s the admin shell on a link-pool domain' do
      signed_in_as(colonel)
      get_shell('links.example.net')

      expect(gate_html_denial?).to be true
    end

    it 'still serves the anchor host' do
      signed_in_as(colonel)
      get_api('example.com')

      expect(last_response.status).to eq(200)
    end

    # Control: the pool member is a fully served, :canonical-classified host —
    # it is the ADMIN surface specifically that is absent on it.
    it 'serves a non-admin endpoint on the link-pool domain (control)' do
      anonymous!
      header 'Host', 'links.example.net'
      get NON_ADMIN_PATH

      expect(last_response.status).to eq(200)
      expect(last_response.headers['O-Domain-Strategy']).to eq('canonical')
    end
  end

  # ===========================================================================
  # 4. An explicit allowed_hosts list is taken LITERALLY
  # ===========================================================================
  describe 'with an explicit site.admin.allowed_hosts' do
    before do
      configure_admin!(
        allowed_hosts: ['admin.example.com'],
        default_domain: 'example.com',
        site_host: 'example.com',
      )
    end

    it 'serves the named admin host' do
      signed_in_as(colonel)
      get_api('admin.example.com')

      expect(last_response.status).to eq(200)
    end

    it 'keeps the role gate in place on the named admin host' do
      signed_in_as(regular)
      get_api('admin.example.com')

      expect(last_response.status).to eq(403)
    end

    it 'does NOT synthesize a www. variant of an explicit entry' do
      signed_in_as(colonel)
      get_api('www.admin.example.com')

      expect(last_response.status).to eq(404)
    end

    it 'replaces the anchor fallback — the canonical host is no longer admitted' do
      signed_in_as(colonel)
      get_api('example.com')

      expect(last_response.status).to eq(404)
    end
  end

  # ===========================================================================
  # 5. Denial shape, and where in the stack the denial happens
  # ===========================================================================
  describe 'the denial response' do
    before { configure_admin!(default_domain: 'example.com', site_host: 'example.com') }

    it 'serves the gate 404 page, not the SPA shell, on /colonel' do
      signed_in_as(colonel)
      get_shell('tenant.example.com')

      expect(last_response.body).to include('404 Not Found')
      expect(last_response.body).not_to include('<!doctype html')
    end

    it 'carries no DomainStrategy headers — the gate short-circuits above it' do
      signed_in_as(colonel)
      get_api('tenant.example.com')

      expect(last_response.headers).not_to have_key('O-Domain-Strategy')
    end

    it 'DOES carry DomainStrategy headers on an admitted host (control)' do
      signed_in_as(colonel)
      get_api('example.com')

      expect(last_response.headers['O-Domain-Strategy']).to eq('canonical')
    end

    it 'sets no session cookie on a denial — the gate runs above Onetime::Session' do
      anonymous!
      get_api('tenant.example.com')

      expect(last_response.headers['set-cookie']).to be_nil
    end

    # Host denials and CIDR denials must be byte-identical: operators tell them
    # apart by the log line, clients cannot tell them apart at all.
    it 'is byte-identical to a CIDR denial on the same surface' do
      signed_in_as(colonel)
      get_api('tenant.example.com')
      host_denial = [last_response.status, last_response.headers.to_h, last_response.body]

      configure_admin!(
        allowed_hosts: ['*'],
        allowed_cidrs: ['10.0.0.0/8'],
        default_domain: 'example.com',
        site_host: 'example.com',
      )
      signed_in_as(colonel)
      get_api('example.com', 'REMOTE_ADDR' => '203.0.113.9')
      cidr_denial = [last_response.status, last_response.headers.to_h, last_response.body]

      expect(cidr_denial.first).to eq(404)
      expect(host_denial).to eq(cidr_denial)
    end
  end

  # ===========================================================================
  # 6. Fail closed when no host can be resolved
  # ===========================================================================
  describe 'when the Host header yields no valid detected host' do
    # DomainParser.basically_valid? rejects this (space + empty label), so
    # Rack::DetectHost writes nil and the gate has nothing to match.
    let(:unparseable_host) { 'ex ample..com' }

    it '404s the API for a colonel' do
      configure_admin!(default_domain: 'example.com', site_host: 'example.com')
      signed_in_as(colonel)
      get_api(unparseable_host)

      expect(last_response.status).to eq(404)
    end

    it '404s the shell for a colonel' do
      configure_admin!(default_domain: 'example.com', site_host: 'example.com')
      signed_in_as(colonel)
      get_shell(unparseable_host)

      expect(last_response.status).to eq(404)
    end

    it 'reaches the app normally with the gate off (control)' do
      configure_admin!(allowed_hosts: ['*'], default_domain: 'example.com', site_host: 'example.com')
      signed_in_as(colonel)
      get_api(unparseable_host)

      expect(last_response.status).to eq(200)
    end

    # A bare-IP Host is the common field shape for a nil detected host: a
    # reverse proxy that does not forward the original Host rewrites it to the
    # upstream address (the nginx `proxy_pass` default), and Rack::DetectHost
    # rejects IP literals and localhost forms outright. The denial log must
    # say so — the remedy is at the proxy (`proxy_set_header Host $host;`,
    # plus site.network.trusted_proxy when the real host only arrives in
    # forwarded headers), not in site.admin.allowed_hosts, which was never
    # consulted and where nothing the operator writes can help.
    describe 'the denial log line' do
      before { configure_admin!(default_domain: 'example.com', site_host: 'example.com') }

      it 'logs the distinct no-detected-host WARN for a bare-IP Host, not the allowlist one' do
        warns = capture_admin_gate_warns!
        signed_in_as(colonel)
        get_api('10.0.0.5')

        expect(last_response.status).to eq(404)
        headlines = warns.map(&:first)
        expect(headlines).to include(a_string_matching(/no host could be detected/))
        expect(headlines).not_to include(a_string_matching(/denied by host allowlist/))
      end

      it 'names the proxy remedy: forward the original Host, and configure proxy trust' do
        warns = capture_admin_gate_warns!
        signed_in_as(colonel)
        get_api('10.0.0.5')

        _, payload = warns.find { |message, _| message.match?(/no host could be detected/) }
        expect(payload).not_to be_nil
        expect(payload[:note]).to match(/proxy_set_header Host/)
        expect(payload[:note]).to match(/site\.network\.trusted_proxy/)
      end

      # Only the diagnosis is distinct; the response must not be. A client
      # probing with a bare-IP Host learns nothing a wrong-host probe would
      # not have taught it.
      it 'keeps the nil-host denial byte-identical to a membership denial' do
        signed_in_as(colonel)
        get_api('tenant.example.com')
        membership_denial = [last_response.status, last_response.headers.to_h, last_response.body]

        get_api('10.0.0.5')
        nil_host_denial = [last_response.status, last_response.headers.to_h, last_response.body]

        expect(nil_host_denial.first).to eq(404)
        expect(nil_host_denial).to eq(membership_denial)
      end
    end
  end

  # ===========================================================================
  # 7. `*` disables the host gate — the documented rollback
  # ===========================================================================
  describe 'with ADMIN_ALLOWED_HOSTS=*' do
    before do
      configure_admin!(allowed_hosts: ['*'], default_domain: 'example.com', site_host: 'example.com')
    end

    it 'serves a colonel on a non-canonical host' do
      signed_in_as(colonel)
      get_api('tenant.example.com')

      expect(last_response.status).to eq(200)
    end

    it 'leaves the role gate in place on a non-canonical host' do
      anonymous!
      get_api('tenant.example.com')

      expect(last_response.status).to eq(401)
    end

    it 'leaves the role gate in place for a non-colonel' do
      signed_in_as(regular)
      get_api('tenant.example.com')

      expect(last_response.status).to eq(403)
    end

    # `*` beside anything else is still `*`. The operator who
    # follows the diagnostic ("set it to *") without deleting the entry that
    # produced it gets the gate they asked for, not a blanket 404 — and the
    # process still boots (Onetime::Config.check_admin_allowed_hosts stays
    # silent for it, see spec/unit/onetime/config/admin_allowed_hosts_spec.rb).
    context 'with `*` beside an unenforceable entry' do
      before do
        configure_admin!(
          allowed_hosts: ['*', '10.0.0.5'],
          default_domain: 'example.com',
          site_host: 'example.com',
        )
      end

      it 'serves a colonel on a non-canonical host' do
        signed_in_as(colonel)
        get_api('tenant.example.com')

        expect(last_response.status).to eq(200)
      end

      it 'serves the shell too' do
        signed_in_as(colonel)
        get_shell('tenant.example.com')

        expect(last_response.status).to eq(200)
      end

      it 'still refuses an anonymous caller at the role gate' do
        anonymous!
        get_api('tenant.example.com')

        expect(last_response.status).to eq(401)
      end
    end
  end

  # ===========================================================================
  # 8. The fail-closed enforcement: an explicit list with nothing enforceable
  # ===========================================================================
  # Onetime::Config.check_admin_allowed_hosts WARNs about this config at boot
  # (spec/unit/onetime/config/admin_allowed_hosts_spec.rb) but does not stop the
  # process — the denial below is what makes that safe. It must DENY, not
  # disable itself: the operator's plain intent was to restrict.
  describe 'with an explicit allowed_hosts that names nothing enforceable' do
    before do
      configure_admin!(allowed_hosts: ['127.0.0.1'], default_domain: 'example.com', site_host: 'example.com')
    end

    it '404s the admin API even on the canonical host' do
      signed_in_as(colonel)
      get_api('example.com')

      expect(last_response.status).to eq(404)
    end

    it '404s the admin shell even on the canonical host' do
      signed_in_as(colonel)
      get_shell('example.com')

      expect(gate_html_denial?).to be true
    end

    it 'leaves non-admin endpoints alone — it is not a blanket outage' do
      anonymous!
      header 'Host', 'example.com'
      get NON_ADMIN_PATH

      expect(last_response.status).to eq(200)
    end
  end

  # ===========================================================================
  # 9. SPOOFING — the security core
  # ===========================================================================
  # Each of these asserts an OUTCOME (still 404) rather than a mechanism, and
  # each is paired with a control proving the spoofing vector is live in this
  # stack. Without the control a green test could mean "the header did nothing
  # anywhere", which would not be evidence about the gate at all.
  describe 'spoofing' do
    describe 'the O-Domain-Context request header' do
      before do
        configure_admin!(
          default_domain: 'example.com',
          site_host: 'example.com',
          domains_enabled: true,
          domain_context: true,
        )
      end

      it 'cannot make a non-allowlisted host reach the admin API' do
        signed_in_as(colonel)
        get_api('tenant.example.com', 'HTTP_O_DOMAIN_CONTEXT' => 'example.com')

        expect(last_response.status).to eq(404)
      end

      it 'cannot make a non-allowlisted host reach the admin shell' do
        signed_in_as(colonel)
        get_shell('tenant.example.com', 'HTTP_O_DOMAIN_CONTEXT' => 'example.com')

        expect(last_response.status).to eq(404)
      end

      # Control: the header IS honoured by DomainStrategy in this exact
      # configuration — it rewrites the display domain. So the 404s above are
      # the admin gate refusing to read it, not the feature being inert.
      it 'is genuinely honoured by DomainStrategy when the gate is off (control)' do
        configure_admin!(
          allowed_hosts: ['*'],
          default_domain: 'example.com',
          site_host: 'example.com',
          domains_enabled: true,
          domain_context: true,
        )
        anonymous!
        header 'Host', 'example.com'
        get NON_ADMIN_PATH, {}, 'HTTP_O_DOMAIN_CONTEXT' => 'other.example.net'

        expect(last_response.status).to eq(200)
        expect(last_response.headers['O-Display-Domain']).to eq('other.example.net')
      end
    end

    # A PERCENT-ENCODED admin path is still an admin path. The Otto router
    # dispatches on Otto::Utils.normalize_path, which decodes first, so a gate
    # that matched the raw SCRIPT_NAME+PATH_INFO would skip both gates and then
    # hand the request to the admin console anyway.
    describe 'percent-encoded spellings of the admin paths' do
      before { configure_admin!(default_domain: 'example.com', site_host: 'example.com') }

      it '404s /%63olonel on a denied host' do
        signed_in_as(colonel)
        header 'Host', 'tenant.example.com'
        get '/%63olonel'

        expect(last_response.status).to eq(404)
      end

      it '404s /colonel%2Fsettings on a denied host' do
        signed_in_as(colonel)
        header 'Host', 'tenant.example.com'
        get '/colonel%2Fsettings'

        expect(last_response.status).to eq(404)
      end

      it '404s an encoded admin API path on a denied host' do
        signed_in_as(colonel)
        header 'Host', 'tenant.example.com'
        get '/api/colonel/%69nfo'

        expect(last_response.status).to eq(404)
      end

      it '404s an encoded admin path from outside the CIDR allowlist' do
        configure_admin!(
          allowed_hosts: ['*'],
          allowed_cidrs: ['10.0.0.0/8'],
          default_domain: 'example.com',
          site_host: 'example.com',
        )
        signed_in_as(colonel)
        header 'Host', 'example.com'
        get '/%63olonel', {}, 'REMOTE_ADDR' => '203.0.113.9'

        expect(last_response.status).to eq(404)
      end

      # Control: the encoded spelling really does reach the admin console once
      # the gate is off — otherwise the 404s above would only prove that the
      # router does not serve it either.
      it 'serves the encoded path on an allowlisted host (control)' do
        signed_in_as(colonel)
        header 'Host', 'example.com'
        header 'Accept', 'application/json'
        get '/api/colonel/%69nfo'

        expect(last_response.status).to eq(200)
        expect(json_body).to have_key('details')
      end
    end

    describe 'forwarded host headers from an untrusted peer' do
      # Neither of these is a TRUSTED peer for the admin gate. Loopback is what
      # Rack::DetectHost's legacy heuristic trusts when site.network.trusted_proxy
      # is unset — which is every containerised install, and is exactly the
      # weakness (#4024) the gate refuses to rely on. Genuine trust is otto's
      # tri-state key, below.
      let(:untrusted_peer) { { 'REMOTE_ADDR' => '203.0.113.9' } }
      let(:heuristic_peer) { { 'REMOTE_ADDR' => '127.0.0.1' } }
      let(:trusted_peer)   { { 'REMOTE_ADDR' => '127.0.0.1', 'otto.via_trusted_proxy' => true } }

      before { configure_admin!(default_domain: 'example.com', site_host: 'example.com') }

      it 'ignores X-Forwarded-Host from an untrusted REMOTE_ADDR' do
        signed_in_as(colonel)
        get_api('tenant.example.com', untrusted_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
      end

      it 'ignores Apx-Incoming-Host from an untrusted REMOTE_ADDR' do
        signed_in_as(colonel)
        get_api('tenant.example.com', untrusted_peer.merge('HTTP_APX_INCOMING_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
      end

      it 'ignores X-Original-Host from an untrusted REMOTE_ADDR' do
        signed_in_as(colonel)
        get_api('tenant.example.com', untrusted_peer.merge('HTTP_X_ORIGINAL_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
      end

      it 'ignores an RFC 7239 Forwarded host from an untrusted REMOTE_ADDR' do
        signed_in_as(colonel)
        get_api('tenant.example.com', untrusted_peer.merge('HTTP_FORWARDED' => 'host=example.com'))

        expect(last_response.status).to eq(404)
      end

      it 'ignores a forwarded header even when it names an allowlisted host and the shell is asked for' do
        signed_in_as(colonel)
        get_shell('tenant.example.com', untrusted_peer.merge('HTTP_X_FORWARDED_HOST' => 'www.example.com'))

        expect(gate_html_denial?).to be true
      end

      # Rack::DetectHost DOES honour this header from a loopback peer with no
      # trusted_proxy configured — the control two examples down proves it — so
      # without the provenance rule this would serve the admin console to
      # anything that could open a connection from a private address while
      # claiming to be the canonical host.
      it 'ignores X-Forwarded-Host from a loopback peer when no proxy trust is configured' do
        signed_in_as(colonel)
        get_api('tenant.example.com', heuristic_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
      end

      it 'ignores Apx-Incoming-Host from a loopback peer when no proxy trust is configured' do
        signed_in_as(colonel)
        get_api('tenant.example.com', heuristic_peer.merge('HTTP_APX_INCOMING_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
      end

      # Control: the header IS live in this stack — Rack::DetectHost really
      # does read it from a loopback peer with no trusted_proxy configured, and
      # DomainStrategy classifies the request by what it read. Without this the
      # two examples above could pass simply because forwarded host headers do
      # nothing here, which would be evidence about the stack, not the gate.
      it 'is genuinely honoured by Rack::DetectHost from a loopback peer (control)' do
        configure_admin!(default_domain: 'example.com', site_host: 'example.com', domains_enabled: true)
        anonymous!
        header 'Host', 'tenant.example.com'
        get NON_ADMIN_PATH, {}, heuristic_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com')

        expect(last_response.status).to eq(200)
        # :canonical is only reachable here if the forwarded header replaced
        # the tenant Host header.
        expect(last_response.headers['O-Domain-Strategy']).to eq('canonical')
      end

      # Control: with otto's trust key set — the operator configured
      # site.network.trusted_proxy and this peer passed it — the forwarded host
      # IS accepted. Trust widens what may be read.
      it 'DOES honour X-Forwarded-Host from a peer otto vouched for (control)' do
        signed_in_as(colonel)
        get_api('tenant.example.com', trusted_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com'))

        expect(last_response.status).to eq(200)
      end

      it 'DOES honour Apx-Incoming-Host from a peer otto vouched for (control)' do
        signed_in_as(colonel)
        get_api('tenant.example.com', trusted_peer.merge('HTTP_APX_INCOMING_HOST' => 'example.com'))

        expect(last_response.status).to eq(200)
      end

      # otto.via_trusted_proxy is tri-state: present-and-false means trust IS
      # configured and this peer FAILED it — strictly worse than absent.
      it 'refuses a forwarded host when otto explicitly distrusted the peer' do
        signed_in_as(colonel)
        get_api(
          'tenant.example.com',
          { 'REMOTE_ADDR' => '127.0.0.1', 'otto.via_trusted_proxy' => false,
            'HTTP_X_FORWARDED_HOST' => 'example.com' },
        )

        expect(last_response.status).to eq(404)
      end

      # The mirror image of the control: a trusted peer forwarding a
      # NON-allowlisted host is denied, so trust widens what is read, never
      # what is admitted.
      it 'denies a trusted-peer forwarded header that names a non-allowlisted host' do
        signed_in_as(colonel)
        get_api('example.com', trusted_peer.merge('HTTP_X_FORWARDED_HOST' => 'tenant.example.com'))

        expect(last_response.status).to eq(404)
      end

      # A forwarded header that AGREES with the Host header changed nothing, so
      # there is nothing to distrust — the ordinary `proxy_set_header Host $host`
      # topology keeps working with no trusted_proxy configured.
      it 'admits a loopback peer whose forwarded header agrees with the Host header' do
        signed_in_as(colonel)
        get_api('example.com', heuristic_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com'))

        expect(last_response.status).to eq(200)
      end

      # And the inverse control: an untrusted peer on an ALLOWLISTED Host still
      # gets through, so the 404s above are about the host, not the peer IP.
      it 'admits an untrusted peer whose Host header is allowlisted' do
        signed_in_as(colonel)
        get_api('example.com', untrusted_peer)

        expect(last_response.status).to eq(200)
      end

      # The remedy in the provenance WARN must demand EXPLICIT proxy CIDRs:
      # filter mode with none configured trusts every private-network peer
      # (add_trusted_proxy(PRIVATE_PROXY_RANGES)), which re-opens exactly the
      # forwarded-host spoofing this denial closes. A WARN that says only
      # "configure trusted_proxy" walks the operator into that hole.
      it 'logs the provenance WARN naming trusted_proxy with explicit proxy CIDRs as the remedy' do
        warns = capture_admin_gate_warns!
        signed_in_as(colonel)
        get_api('tenant.example.com', heuristic_peer.merge('HTTP_X_FORWARDED_HOST' => 'example.com'))

        expect(last_response.status).to eq(404)
        _, payload = warns.find { |message, _| message.match?(/untrusted peer/) }
        expect(payload).not_to be_nil
        expect(payload[:note]).to match(/site\.network\.trusted_proxy/)
        expect(payload[:note]).to match(/explicit/i)
        expect(payload[:note]).to match(/CIDR/i)
      end
    end
  end

  # ===========================================================================
  # 10. The CIDR gate judges the FULL client IP, not the privacy-masked one
  # ===========================================================================
  #
  # IPPrivacyMiddleware is mounted ABOVE this gate in the same universal stack
  # and zeroes the last IPv4 octet before AdminNetworkIsolation runs, so
  # env['otto.client_ip'] reads 203.0.113.0 for a client at 203.0.113.9. The
  # gate therefore judges membership through env['otto.ip_match'] — the
  # verdict-only closure that middleware installs over the PRE-MASK address.
  #
  # Every other CIDR example in this file puts the client a whole /8 outside
  # the allowlist, which 404s under either reading and so says nothing about
  # WHICH address was judged. This one is built so the two readings disagree,
  # in both directions:
  #
  #   allowed_cidrs 203.0.113.9/32 — full precision ADMITS, masked DENIES: an
  #     operator's single-admin-IP entry locking them out of their own console.
  #   allowed_cidrs 203.0.113.0/32 — full precision DENIES, masked ADMITS: the
  #     masked network address admitting every neighbor that shares the /24.
  #
  # Both halves flip if the gate ever goes back to matching the masked value.
  describe 'the CIDR gate at /32 precision' do
    it 'admits the client its own /32 names, and denies the /32 of its masked form' do
      configure_admin!(
        allowed_hosts: ['*'],
        allowed_cidrs: ['203.0.113.9/32'],
        default_domain: 'example.com',
        site_host: 'example.com',
      )
      signed_in_as(colonel)
      get_api('example.com', 'REMOTE_ADDR' => '203.0.113.9')

      expect(last_response.status).to eq(200)
      expect(json_body).to have_key('details')

      # The inverse. 203.0.113.0 is what the mask produces and is NOT the
      # client; admitting it would mean the gate judged the masked value.
      configure_admin!(
        allowed_hosts: ['*'],
        allowed_cidrs: ['203.0.113.0/32'],
        default_domain: 'example.com',
        site_host: 'example.com',
      )
      signed_in_as(colonel)
      get_api('example.com', 'REMOTE_ADDR' => '203.0.113.9')

      expect(last_response.status).to eq(404)
    end
  end
end
