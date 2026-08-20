# apps/web/auth/spec/integration/full/public_host_email_link_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — the DELIVERED transactional email link (#4221)
# =============================================================================
#
# THE DEFECT. Rodauth composes every `*_email_link` through `token_link` ->
# `route_url` -> `base_url`, and stock `base_url` is
# `"#{request.scheme}://#{request.host}"`. Behind the custom-domain proxy
# `Host:` has been rewritten to the origin target and the host the visitor
# actually used arrives in `Apx-Incoming-Host`, so the link in the email named
# the canonical host — a host the recipient never visited, and one where
# Auth::SigninGate answers 404 on any install whose global sign-in is off.
#
# THE FIX under test: config/overrides/public_base_url.rb overrides `base_url`
# (and adds `public_display_domain` for branding) through Auth::PublicHost.
#
# WHY THIS FILE EXISTS ALONGSIDE unit/public_base_url_spec.rb. That unit spec
# proves the policy and proves the override is wired into a real Rodauth
# configuration. It stops at `base_url`. Nothing there proves that the string
# a RECIPIENT would click carries the public host: the email blocks
# (config/email/*.rb) read `base_url` and `public_display_domain` themselves,
# the mail templates compose the body, and Auth::Config::Email::Delivery hands
# the rendered result to Onetime::Jobs::Publisher. These examples drive the
# real mounted Rack stack end to end and assert on what Delivery emits.
#
# WHY RESET-PASSWORD AND NOT THE MAGIC LINK. The three email blocks changed by
# #4221 (email_auth, reset_password, verify_account) share ONE seam —
# `base_url` — and reset-password is the only one of the three reachable in
# this lane: spec/auth.test.yaml pins `email_auth: false` and
# `verify_account: false`, so neither route is mounted and an example against
# either would skip vacuously. Enabling email_auth here is not a local choice:
# it turns on `use_multi_phase_login?` for every full-mode spec in the shared
# process. So reset-password stands in for the family, and the unit spec
# covers `base_url` itself, which is what the other two read.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   tests/lanes/run full-sqlite
#   # or directly:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/public_host_email_link_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'delivered email links use the public host (#4221)', type: :integration do
  include Rack::Test::Methods

  # The canonical host installed for this file (see before(:all)).
  CANONICAL_HOST = 'canonical.example.org'

  before(:all) do
    boot_onetime_app

    # The canonical SET (what Auth::PublicHost consults through
    # canonical_host?) is class-level state on DomainStrategy, normally
    # populated when the middleware is first instantiated. Two reasons to
    # rebuild it here rather than read whatever boot left behind:
    #
    #   1. `origin_host` below reads it before any request has been made.
    #   2. The test config's site.host is `127.0.0.1:3000`. An IP literal does
    #      not parse as a domain, so Chooserator cannot classify a request to
    #      it :canonical — it degrades to :invalid, Auth::SigninGate fails
    #      closed, and the canonical-host example 404s before Rodauth composes
    #      anything. A synthetic `features.domains.default` gives the canonical
    #      arm a real hostname to match, the same trick bin/visual uses
    #      (DEFAULT_DOMAIN=canonical.example.org).
    @original_domains_config = OT.conf&.dig('features', 'domains') || {}

    # The custom-domain feature ships OFF in the test config (DOMAINS_ENABLED),
    # and with it off DomainStrategy short-circuits: every request classifies
    # :canonical and env['onetime.display_domain'] IS the canonical host, so
    # Auth::PublicHost would decline on every example here and all of them
    # would pass vacuously against the unchanged stock derivation. Flip the
    # runtime flag rather than the env var — the lane env is shared — exactly
    # as signin_gate_enforcement_spec.rb does, and restore after.
    @original_features        = Onetime::Runtime.features
    Onetime::Runtime.features = @original_features.with(domains_enabled: true)
  end

  after(:all) do
    Onetime::Runtime.features = @original_features if @original_features
    Onetime::Middleware::DomainStrategy.initialize_from_config(@original_domains_config || {})
  end

  let(:run_id) { SecureRandom.hex(6) }

  # The origin target a Host-rewriting proxy puts in `Host:`. Also the host
  # every assertion below uses as the NEGATIVE — it is what the defect
  # produced.
  let(:origin_host) { CANONICAL_HOST }

  # tr('_', '-'): an underscore is not legal in a hostname label and
  # DomainStrategy silently falls back to the canonical host for one
  # (basically_valid? fails), which would make the example pass vacuously.
  let(:tenant_domain) { "mail-#{run_id}.tenant-example.com" }

  let(:account_email) { unique_test_email('reset') }

  # A registered custom domain that has opted into sign-in.
  #
  # The SigninConfig is a PRECONDITION, not the subject: Auth::SigninGate lists
  # :reset_password_request among its SIGNIN_ROUTES, so on a custom host with
  # no opt-in the POST 404s before Rodauth ever composes an email and every
  # example here would fail on an empty mailbox instead of a wrong host.
  # restrict_to is left unset — an enabled SigninConfig with no restriction
  # resolves :unrestricted, so Auth::RestrictTo cannot interfere either.
  let!(:tenant) { build_signin_domain(tenant_domain) }

  let!(:account_id) { seed_account_with_password(account_email) }

  def build_signin_domain(host)
    owner = Onetime::Customer.new(email: "owner-#{run_id}@test.local")
    owner.save
    org = Onetime::Organization.create!("PublicHost Org #{run_id}", owner, 'contact@test.local')

    domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: domain.identifier,
      enabled: true,
      signin_enabled: true,
      sso_enabled: false,
    )

    (@fixtures ||= []) << [org, domain, owner, host]
    domain
  end

  before do
    # Install the synthetic canonical set, then FREEZE it.
    #
    # AuthRequestHelper#app rebuilds the Rack URL map on every call, and every
    # rebuild re-instantiates DomainStrategy, which re-runs
    # initialize_from_config against the on-disk config — silently reverting
    # anything set in before(:all) the moment the first request is made. The
    # stub is what makes the assignment stick for the duration of an example;
    # after(:all) restores the real config for the rest of the suite.
    Onetime::Middleware::DomainStrategy.initialize_from_config(
      @original_domains_config.merge('enabled' => true, 'default' => CANONICAL_HOST),
    )
    allow(Onetime::Middleware::DomainStrategy).to receive(:initialize_from_config)

    # The delivery seam. Auth::Config::Email::Delivery's send_email hook hands
    # Rodauth's rendered Mail object to the publisher as a plain hash; capturing
    # it here is the closest observation point to an actual send.
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end
  end

  after do
    Array(@fixtures).each do |org, domain, owner, host|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
      Onetime::CustomDomain.display_domain_index.remove(host)
      domain.destroy!
      org.destroy!
      owner.destroy!
    rescue StandardError => ex
      warn "[public_host_email_link spec] cleanup failed for #{host}: #{ex.message}"
    end
  end

  # POST the reset request with an explicit topology.
  #
  # CSRF matters: check_csrf runs before the Rodauth route, so a token-less POST
  # would be rejected upstream and the example would pass for the wrong reason.
  # csrf_json_post's GET /auth carries the same headers, so the token is minted
  # on the same host the POST claims.
  #
  # @param host [String] the `Host:` header (what the proxy rewrote it to)
  # @param forwarded [String, nil] `Apx-Incoming-Host` (what the browser asked for)
  def request_password_reset(host:, forwarded: nil)
    clear_cookies
    header 'Host', host
    header 'Apx-Incoming-Host', forwarded
    csrf_json_post('/auth/reset-password-request', login: account_email)
  end

  # The one email Rodauth composed for this request.
  def delivered_email
    expect(@delivered.size).to eq(1),
      "expected exactly one delivered email, got #{@delivered.size}. " \
      "Last response: #{last_response.status} #{last_response.body.to_s[0, 300]}"
    @delivered.first
  end

  # The clickable reset URL, lifted out of the rendered text body the same way
  # a recipient's mail client would find it.
  #
  # The path is `/reset-password`, NOT `/auth/reset-password`: Rodauth's
  # `route_path` is `"#{prefix}/#{route}"` with prefix deliberately empty
  # (Rack::URLMap already strips the /auth mount, so setting it would
  # double-strip — see #3323), and the SPA owns `/reset-password?key=` at the
  # site root (src/router/guards.routes.ts:407). That split is not this
  # issue's subject; asserting the literal shape here means a future
  # SCRIPT_NAME-aware `route_path` shows up as a failure to be looked at
  # rather than a silent change to what recipients click.
  def reset_link
    body = delivered_email[:body].to_s
    link = body[%r{https?://\S+?/reset-password\?key=\S+}]
    expect(link).not_to be_nil,
      "no /reset-password link found in the delivered body:\n#{body[0, 600]}"
    link
  end

  describe 'behind a Host-rewriting proxy (Apx-Incoming-Host)' do
    before { request_password_reset(host: origin_host, forwarded: tenant_domain) }

    it 'sends a reset link on the host the browser asked for, not the origin target' do
      expect(URI.parse(reset_link).host).to eq(tenant_domain)
      expect(reset_link).not_to include(origin_host)
    end

    it 'delivers a WORKING credential — the emailed key actually resets the password' do
      # The point of the example: without it, everything above would still pass
      # if the host rewrite had mangled the token, and the recipient would get
      # a correctly-addressed link that fails on arrival. Redeeming the key
      # Rodauth put IN THE EMAIL is the only assertion that rules that out.
      # (The stored column cannot be compared byte-for-byte — hmac_secret is
      # set, so what the email carries is the token and what the row holds is
      # its HMAC.)
      key          = CGI.parse(URI.parse(reset_link).query.to_s)['key'].first.to_s
      new_password = 'RedeemedByTheLink123!'

      header 'Host', origin_host
      header 'Apx-Incoming-Host', tenant_domain
      response = csrf_json_post(
        '/auth/reset-password',
        key: key, password: new_password, 'password-confirm': new_password,
      )

      expect(response.status).to be_between(200, 302),
        "redeeming the emailed key returned #{response.status}: #{response.body.to_s[0, 300]}"
      expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0),
        'the reset key row survived redemption — the key was not actually consumed'
    end

    it 'brands the subject with the public host too' do
      # public_display_domain, not request.host: a link on the tenant domain
      # inside an email that says "Reset your password (canonical.example)"
      # reads as a phishing attempt.
      expect(delivered_email[:subject].to_s).to include(tenant_domain)
      expect(delivered_email[:subject].to_s).not_to include(origin_host)
    end
  end

  describe 'when the proxy preserves the custom domain in Host' do
    it 'still sends the link on that domain' do
      request_password_reset(host: tenant_domain)

      expect(URI.parse(reset_link).host).to eq(tenant_domain)
    end
  end

  describe 'on the canonical host' do
    it 'leaves the stock derivation alone — no over-rewrite' do
      # Auth::PublicHost declines for canonical-set hosts, so this link is
      # whatever Rodauth would have produced before #4221. The example is the
      # guard against a fix that rewrites every host.
      request_password_reset(host: origin_host)

      expect(reset_link).to include(origin_host)
      expect(reset_link).not_to include(tenant_domain)
    end
  end
end
