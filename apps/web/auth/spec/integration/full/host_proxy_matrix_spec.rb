# apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack) — host and proxy simulation matrix
# =============================================================================
#
# One table of request shapes — Host, X-Forwarded-Host, Apx-Incoming-Host,
# X-Original-Host, RFC 7239 Forwarded, a doubled or comma-joined value, a
# loopback or a public connecting peer — crossed with the state of the
# CustomDomain record the request names (verified, unverified, unreadable)
# and with the canonical-host configuration. Each row is sent through the
# mounted stack and the row states what comes out:
#
#   rack_host       Rack::Request#host after the stack ran
#   detected        Rack::DetectHost's result
#   display         env['onetime.display_domain']
#   strategy        env['onetime.domain_strategy']
#   origin          the origin auth URLs build on. Asserted for both readers:
#                   the Proc installed as OmniAuth.config.full_host (SSO
#                   redirect_uri / callback_url, SAML ACS and SP entity ID)
#                   and Auth::PublicHost.allowlisted_base_url (Rodauth
#                   base_url, hence every emailed link)
#   tenant_host     the host tenant SSO credentials are keyed on
#                   (Auth::Config::Features::OmniAuth.public_host_for)
#   webauthn_host   Auth::PublicHost.webauthn_host; nil means
#                   config/features/webauthn.rb falls back to rack_host
#
# A second, shorter table drives the emitters themselves for the rows that
# matter most: the redirect_uri in the IdP redirect of POST /auth/sso/entra,
# and the link and subject of the delivered reset-password email.
#
# THIS FILE PINS CURRENT BEHAVIOUR. It is the baseline the host work in
# #4223, #4220 and #4384 is measured against, so a row says what the stack
# does today, not what it should do. Rows whose outcome one of those issues
# is expected to change carry `changes_with:` naming the issue.
#
# The scenarios that used to live in spec/unit/omniauth_full_host_spec.rb
# are here too: as request rows where a request produces the state, and
# under 'env states the request rows do not reach' where none does.
#
# Related, not duplicated here:
#   - tenant_sso_proxy_host_spec.rb: tenant SSO outcomes on a rewritten Host
#   - public_host_email_link_spec.rb: the emailed key redeems
#
# RUN:
#   tests/lanes/run full-sqlite --only \
#     apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'
require 'rack/test'

module HostProxyMatrix
  # A host with no CustomDomain record, on a registrable domain that is not
  # a peer of any canonical host used below.
  UNREGISTERED = 'unregistered.tenant-example.com'

  # A public address for the connecting peer. With no trusted-proxy
  # configuration (the default, and the test configuration) DetectHost
  # honours forwarded host headers from a private or loopback peer only.
  PUBLIC_PEER = '203.0.113.7'

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

  # ---------------------------------------------------------------------------
  # Domains feature ON. features.domains.default = canonical.example.org,
  # site.host = 127.0.0.1:3000 unless the row sets `site_host:`.
  #
  # Every row sends X-Forwarded-Proto: https unless it sets `proto: nil`.
  # ---------------------------------------------------------------------------
  DOMAINS_ON = [
    # --- Host only -----------------------------------------------------------
    { id: 'H01', case: 'canonical host in Host',
      headers: { 'Host' => '{canonical}' },
      **CANONICAL },
    { id: 'H02', case: 'verified custom domain in Host (proxy preserves Host)',
      headers: { 'Host' => '{tenant}' },
      rack_host: '{tenant}', **TENANT },
    { id: 'H03', case: 'unregistered host in Host',
      headers: { 'Host' => UNREGISTERED },
      rack_host: UNREGISTERED, detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'H04', case: 'canonical host with a non-default port',
      headers: { 'Host' => '{canonical}:8443' },
      **CANONICAL, origin: 'https://{canonical}:8443' },
    { id: 'H05', case: 'verified custom domain with a non-default port',
      headers: { 'Host' => '{tenant}:8443' },
      rack_host: '{tenant}', **TENANT, origin: 'https://{tenant}:8443' },
    { id: 'H06', case: 'verified custom domain with the default port spelled out',
      headers: { 'Host' => '{tenant}:443' },
      rack_host: '{tenant}', **TENANT },
    { id: 'H07', case: 'localhost, which DetectHost does not accept',
      headers: { 'Host' => 'localhost:3000' }, proto: nil,
      rack_host: 'localhost', detected: nil, display: '{canonical}', strategy: :invalid,
      origin: 'http://{canonical}:3000', tenant_host: nil, webauthn_host: nil },
    { id: 'H08', case: 'the IP-literal site.host itself',
      headers: { 'Host' => SITE_HOST }, proto: nil,
      rack_host: '127.0.0.1', detected: nil, display: '{canonical}', strategy: :invalid,
      origin: 'http://{canonical}:3000', tenant_host: nil, webauthn_host: nil },
    { id: 'H09', case: 'a host that is not a valid hostname',
      headers: { 'Host' => 'bad_host.tenant-example.com' },
      rack_host: 'bad_host.tenant-example.com', detected: nil, display: '{canonical}', strategy: :invalid,
      origin: CANONICAL_ORIGIN, tenant_host: nil, webauthn_host: nil },

    # --- Doubled Host (#4517) ------------------------------------------------
    # Rack cannot parse the authority: host is nil and base_url repeats the
    # header verbatim. DetectHost keeps the first element.
    { id: 'D01', case: 'doubled canonical Host',
      headers: { 'Host' => '{canonical}, {canonical}' },
      **CANONICAL, rack_host: nil, rack_base_url: 'https://{canonical}, {canonical}' },
    { id: 'D02', case: 'doubled verified custom domain Host',
      headers: { 'Host' => '{tenant}, {tenant}' },
      rack_host: nil, rack_base_url: 'https://{tenant}, {tenant}', **TENANT },
    # The port is in the unparseable authority and nowhere in configuration,
    # so the origin comes out without it.
    { id: 'D03', case: 'doubled canonical Host on a non-default port that is not configured',
      headers: { 'Host' => '{canonical}:8443, {canonical}:8443' },
      changes_with: '#4223',
      **CANONICAL, rack_host: nil, rack_base_url: 'https://{canonical}:8443, {canonical}:8443' },
    # No hostname survives anywhere: rack_host and webauthn_host are both
    # nil, so the WebAuthn rp_id fallback has nothing to return.
    { id: 'D04', case: 'doubled IP-literal site.host',
      headers: { 'Host' => "#{SITE_HOST}, #{SITE_HOST}" }, proto: nil,
      changes_with: '#4223',
      rack_host: nil, rack_base_url: "http://#{SITE_HOST}, #{SITE_HOST}",
      detected: nil, display: '{canonical}', strategy: :invalid,
      origin: 'http://{canonical}', tenant_host: nil, webauthn_host: nil },

    # --- Forwarded host from a loopback peer ---------------------------------
    # Rack's own host stays on Host: StripForwardedHost removes
    # X-Forwarded-Host and Forwarded before anything reads request.host.
    { id: 'F01', case: 'Host rewritten to the origin target, tenant in Apx-Incoming-Host',
      headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      rack_host: '{canonical}', **TENANT },
    { id: 'F02', case: 'tenant in X-Forwarded-Host',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      rack_host: '{canonical}', **TENANT },
    { id: 'F03', case: 'tenant in X-Original-Host',
      headers: { 'Host' => '{canonical}', 'X-Original-Host' => '{tenant}' },
      rack_host: '{canonical}', **TENANT },
    { id: 'F04', case: 'comma-joined X-Forwarded-Host, tenant first',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => "{tenant}, #{UNREGISTERED}" },
      changes_with: '#4384',
      rack_host: '{canonical}', **TENANT },
    { id: 'F05', case: 'comma-joined X-Forwarded-Host, tenant last',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => "#{UNREGISTERED}, {tenant}" },
      changes_with: '#4384',
      rack_host: '{canonical}', detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'F06', case: 'X-Forwarded-Host outranks Apx-Incoming-Host',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => UNREGISTERED, 'Apx-Incoming-Host' => '{tenant}' },
      changes_with: '#4384',
      rack_host: '{canonical}', detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'F07', case: 'unregistered host in X-Forwarded-Host',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => UNREGISTERED },
      rack_host: '{canonical}', detected: UNREGISTERED, display: UNREGISTERED, strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    # Only the hostname is swapped: the port of the origin hop rides along.
    { id: 'F08', case: 'origin target on a port, tenant in Apx-Incoming-Host',
      headers: { 'Host' => SITE_HOST, 'Apx-Incoming-Host' => '{tenant}' }, proto: nil,
      changes_with: '#4223',
      rack_host: '127.0.0.1', **TENANT, origin: 'http://{tenant}:3000' },

    # --- RFC 7239 Forwarded --------------------------------------------------
    # Never a host source. Under the X-Forwarded family the stack pins, its
    # proto= is not read either.
    { id: 'R01', case: 'Forwarded host= names the tenant, no X-Forwarded-Proto',
      headers: { 'Host' => '{canonical}', 'Forwarded' => 'for=198.51.100.1;host={tenant};proto=https' }, proto: nil,
      **CANONICAL, origin: 'http://{canonical}' },
    { id: 'R02', case: 'Forwarded host= names the tenant alongside X-Forwarded-Proto',
      headers: { 'Host' => '{canonical}', 'Forwarded' => 'for=198.51.100.1;host={tenant};proto=http' },
      **CANONICAL },

    # --- Forwarded host from a public peer -----------------------------------
    { id: 'U01', case: 'X-Forwarded-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      **CANONICAL },
    { id: 'U02', case: 'Apx-Incoming-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      **CANONICAL },
    { id: 'U03', case: 'X-Original-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Original-Host' => '{tenant}' },
      **CANONICAL },
    { id: 'U04', case: 'Forwarded host= from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'Forwarded' => 'host={tenant};proto=https' },
      **CANONICAL },
    { id: 'U05', case: 'verified custom domain in Host from a public peer',
      peer: :public, headers: { 'Host' => '{tenant}' },
      rack_host: '{tenant}', **TENANT },

    # --- Record state: registered, not verified ------------------------------
    # The request still classifies :custom and WebAuthn still names the
    # domain. Auth URLs do not build on it, and with no canonical candidate
    # in the request they land on configured site.host.
    { id: 'V01', case: 'unverified custom domain in Apx-Incoming-Host',
      record: :unverified, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      rack_host: '{canonical}', **TENANT, origin: SITE_HOST_ORIGIN, tenant_host: nil },
    { id: 'V02', case: 'unverified custom domain in Host',
      record: :unverified, headers: { 'Host' => '{tenant}' },
      rack_host: '{tenant}', **TENANT, origin: SITE_HOST_ORIGIN, tenant_host: nil },

    # --- Record state: the datastore read fails ------------------------------
    # DomainStrategy classifies the host :invalid; Auth::PublicHost declines
    # it. WebAuthn gets no host and falls back to rack_host.
    { id: 'X01', case: 'read failure, tenant in Apx-Incoming-Host',
      record: :read_fails, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      changes_with: '#4220',
      rack_host: '{canonical}', detected: '{tenant}', display: '{tenant}', strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'X02', case: 'read failure, tenant in Host',
      record: :read_fails, headers: { 'Host' => '{tenant}' },
      changes_with: '#4220',
      rack_host: '{tenant}', detected: '{tenant}', display: '{tenant}', strategy: :invalid,
      origin: SITE_HOST_ORIGIN, tenant_host: nil, webauthn_host: nil },
    { id: 'X03', case: 'read failure, canonical host',
      record: :read_fails, headers: { 'Host' => '{canonical}' },
      **CANONICAL },

    # --- Canonical-host configuration ----------------------------------------
    { id: 'C01', case: 'hostname site.host on a configured non-default port',
      site_host: 'secrets.internal.example.net:8443',
      headers: { 'Host' => 'secrets.internal.example.net:8443' },
      rack_host: 'secrets.internal.example.net', detected: 'secrets.internal.example.net',
      display: 'secrets.internal.example.net', strategy: :canonical,
      origin: 'https://secrets.internal.example.net:8443', tenant_host: nil,
      webauthn_host: 'secrets.internal.example.net' },
    # The configured port is kept although the authority cannot be parsed.
    { id: 'C02', case: 'doubled Host, hostname site.host on a configured non-default port',
      site_host: 'secrets.internal.example.net:8443',
      headers: { 'Host' => 'secrets.internal.example.net:8443, secrets.internal.example.net:8443' },
      rack_host: nil, detected: 'secrets.internal.example.net',
      display: 'secrets.internal.example.net', strategy: :canonical,
      origin: 'https://secrets.internal.example.net:8443', tenant_host: nil,
      webauthn_host: 'secrets.internal.example.net' },
    # features.domains.default and site.host share a hostname; site.host
    # carries the port and is the authority the origin resolves to.
    { id: 'C03', case: 'doubled Host, site.host shares its hostname with the default domain',
      site_host: '{canonical}:7143',
      headers: { 'Host' => '{canonical}:7143, {canonical}:7143' },
      **CANONICAL, rack_host: nil, origin: 'https://{canonical}:7143' },
    { id: 'C04', case: 'split deployment, request on site.host',
      site_host: 'app.operator.example.net',
      headers: { 'Host' => 'app.operator.example.net' },
      rack_host: 'app.operator.example.net', detected: 'app.operator.example.net',
      display: 'app.operator.example.net', strategy: :canonical,
      origin: 'https://app.operator.example.net', tenant_host: nil,
      webauthn_host: 'app.operator.example.net' },
    { id: 'C05', case: 'split deployment, request on the default domain',
      site_host: 'app.operator.example.net',
      headers: { 'Host' => '{canonical}' },
      **CANONICAL },
    { id: 'C06', case: 'split deployment, tenant in Apx-Incoming-Host',
      site_host: 'app.operator.example.net',
      headers: { 'Host' => 'app.operator.example.net', 'Apx-Incoming-Host' => '{tenant}' },
      rack_host: 'app.operator.example.net', **TENANT },
    # A host under a canonical anchor's registrable domain classifies
    # :canonical without being in the canonical set. Auth URLs fall to
    # site.host; WebAuthn takes the host as sent.
    { id: 'C07', case: 'unregistered peer of the default domain in X-Forwarded-Host',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => 'peer.example.org' },
      changes_with: '#4223',
      rack_host: '{canonical}', detected: 'peer.example.org', display: 'peer.example.org',
      strategy: :canonical, origin: SITE_HOST_ORIGIN, tenant_host: nil,
      webauthn_host: 'peer.example.org' },
  ].freeze

  # ---------------------------------------------------------------------------
  # Domains feature OFF. DomainStrategy classifies nothing: every request is
  # :canonical and display_domain is site.host as configured, port included.
  # DetectHost still runs, and a verified custom domain it detects is still
  # honoured for auth URLs.
  # ---------------------------------------------------------------------------
  OFF = {
    detected: nil,
    display: SITE_HOST,
    strategy: :canonical,
    origin: "http://#{SITE_HOST}",
    tenant_host: nil,
    webauthn_host: nil,
  }.freeze

  DOMAINS_OFF = [
    { id: 'N01', case: 'IP-literal site.host in Host',
      headers: { 'Host' => SITE_HOST }, proto: nil,
      rack_host: '127.0.0.1', **OFF },
    # The configured port is kept although the authority cannot be parsed.
    { id: 'N02', case: 'doubled IP-literal site.host',
      headers: { 'Host' => "#{SITE_HOST}, #{SITE_HOST}" }, proto: nil,
      changes_with: '#4223',
      rack_host: nil, rack_base_url: "http://#{SITE_HOST}, #{SITE_HOST}", **OFF },
    { id: 'N03', case: 'unregistered host in Host',
      headers: { 'Host' => UNREGISTERED },
      rack_host: UNREGISTERED, **OFF, detected: UNREGISTERED, origin: SITE_HOST_ORIGIN },
    { id: 'N04', case: 'verified custom domain in Host',
      headers: { 'Host' => '{tenant}' },
      rack_host: '{tenant}', **OFF, detected: '{tenant}', origin: TENANT_ORIGIN, tenant_host: '{tenant}' },
    # Only the hostname is swapped: the port of the origin hop rides along.
    { id: 'N05', case: 'origin target on a port, verified custom domain in Apx-Incoming-Host',
      headers: { 'Host' => SITE_HOST, 'Apx-Incoming-Host' => '{tenant}' }, proto: nil,
      changes_with: '#4223',
      rack_host: '127.0.0.1', **OFF, detected: '{tenant}', origin: 'http://{tenant}:3000', tenant_host: '{tenant}' },
    { id: 'N06', case: 'unverified custom domain in Apx-Incoming-Host',
      record: :unverified, headers: { 'Host' => SITE_HOST, 'Apx-Incoming-Host' => '{tenant}' }, proto: nil,
      rack_host: '127.0.0.1', **OFF, detected: '{tenant}' },
    { id: 'N07', case: 'read failure, verified custom domain in Apx-Incoming-Host',
      record: :read_fails, headers: { 'Host' => SITE_HOST, 'Apx-Incoming-Host' => '{tenant}' }, proto: nil,
      changes_with: '#4220',
      rack_host: '127.0.0.1', **OFF, detected: '{tenant}' },
    { id: 'N08', case: 'Apx-Incoming-Host from a public peer',
      peer: :public, headers: { 'Host' => SITE_HOST, 'Apx-Incoming-Host' => '{tenant}' }, proto: nil,
      rack_host: '127.0.0.1', **OFF },
    { id: 'N09', case: 'unregistered host in X-Forwarded-Host',
      headers: { 'Host' => SITE_HOST, 'X-Forwarded-Host' => UNREGISTERED }, proto: nil,
      rack_host: '127.0.0.1', **OFF, detected: UNREGISTERED },

    # --- Canonical-host configuration ----------------------------------------
    { id: 'N10', case: 'local development host that is itself site.host',
      site_host: 'localhost:7143',
      headers: { 'Host' => 'localhost:7143' }, proto: nil,
      rack_host: 'localhost', **OFF, display: 'localhost:7143', origin: 'http://localhost:7143' },
    { id: 'N11', case: 'hostname site.host in Host',
      site_host: 'onetime.example.net',
      headers: { 'Host' => 'onetime.example.net' },
      rack_host: 'onetime.example.net', **OFF, detected: 'onetime.example.net',
      display: 'onetime.example.net', origin: 'https://onetime.example.net',
      webauthn_host: 'onetime.example.net' },
    # site.host spells out the default port. It appears once in display and
    # not at all in the origin.
    { id: 'N12', case: 'doubled Host, site.host spells out the default port',
      site_host: 'onetime.example.net:443',
      headers: { 'Host' => 'onetime.example.net, onetime.example.net' },
      rack_host: nil, **OFF, detected: 'onetime.example.net',
      display: 'onetime.example.net:443', origin: 'https://onetime.example.net' },
    { id: 'N13', case: 'a host other than site.host, which DetectHost does not accept',
      site_host: 'onetime.example.net',
      headers: { 'Host' => 'localhost:3000' }, proto: nil,
      rack_host: 'localhost', **OFF, display: 'onetime.example.net',
      origin: 'http://onetime.example.net:3000', webauthn_host: 'onetime.example.net' },
  ].freeze

  OBSERVED_KEYS = [:rack_host, :detected, :display, :strategy, :origin, :tenant_host, :webauthn_host].freeze

  # ---------------------------------------------------------------------------
  # Emitter rows: what POST /auth/sso/entra hands the IdP, and what the
  # reset-password email carries.
  #
  #   idp           :tenant or :platform — whose Entra tenant the redirect
  #                 names — or nil when the response is not an IdP redirect
  #   redirect_uri  origin of the redirect_uri parameter
  #   sso_location  suffix of Location when it is not an IdP redirect
  #   link          origin of the emailed reset link, nil when none is sent
  #   brand         host named in the email subject
  #   reset_status  status of the reset request when no email is sent
  # ---------------------------------------------------------------------------
  EMITTERS_ON = [
    { id: 'E01', case: 'canonical host in Host',
      headers: { 'Host' => '{canonical}' },
      idp: :platform, redirect_uri: CANONICAL_ORIGIN, link: CANONICAL_ORIGIN, brand: '{canonical}' },
    { id: 'E02', case: 'Host rewritten to the origin target, tenant in Apx-Incoming-Host',
      headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      idp: :tenant, redirect_uri: TENANT_ORIGIN, link: TENANT_ORIGIN, brand: '{tenant}' },
    { id: 'E03', case: 'verified custom domain in Host',
      headers: { 'Host' => '{tenant}' },
      idp: :tenant, redirect_uri: TENANT_ORIGIN, link: TENANT_ORIGIN, brand: '{tenant}' },
    { id: 'E04', case: 'tenant in X-Forwarded-Host',
      headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      idp: :tenant, redirect_uri: TENANT_ORIGIN, link: TENANT_ORIGIN, brand: '{tenant}' },
    { id: 'E05', case: 'doubled canonical Host',
      headers: { 'Host' => '{canonical}, {canonical}' },
      idp: :platform, redirect_uri: CANONICAL_ORIGIN, link: CANONICAL_ORIGIN, brand: '{canonical}' },
    { id: 'E06', case: 'doubled verified custom domain Host',
      headers: { 'Host' => '{tenant}, {tenant}' },
      idp: :tenant, redirect_uri: TENANT_ORIGIN, link: TENANT_ORIGIN, brand: '{tenant}' },
    { id: 'E07', case: 'canonical host with a non-default port',
      headers: { 'Host' => '{canonical}:8443' },
      idp: :platform, redirect_uri: 'https://{canonical}:8443', link: 'https://{canonical}:8443', brand: '{canonical}' },
    { id: 'E08', case: 'X-Forwarded-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'X-Forwarded-Host' => '{tenant}' },
      idp: :platform, redirect_uri: CANONICAL_ORIGIN, link: CANONICAL_ORIGIN, brand: '{canonical}' },
    { id: 'E09', case: 'Apx-Incoming-Host from a public peer',
      peer: :public, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      idp: :platform, redirect_uri: CANONICAL_ORIGIN, link: CANONICAL_ORIGIN, brand: '{canonical}' },
    { id: 'E10', case: 'Forwarded host= names the tenant',
      headers: { 'Host' => '{canonical}', 'Forwarded' => 'for=198.51.100.1;host={tenant};proto=https' },
      idp: :platform, redirect_uri: CANONICAL_ORIGIN, link: CANONICAL_ORIGIN, brand: '{canonical}' },
    { id: 'E11', case: 'unverified custom domain in Apx-Incoming-Host',
      record: :unverified, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      idp: nil, sso_location: '/signin?auth_error=sso_domain_unverified',
      link: SITE_HOST_ORIGIN, brand: SITE_HOST },
    # The sign-in gates answer before either emitter runs: no IdP redirect
    # and no email.
    { id: 'E12', case: 'read failure, tenant in Apx-Incoming-Host',
      record: :read_fails, headers: { 'Host' => '{canonical}', 'Apx-Incoming-Host' => '{tenant}' },
      changes_with: '#4220',
      idp: nil, sso_location: '/signin?auth_error=sso_failed',
      link: nil, reset_status: 503 },
  ].freeze

  EMITTERS_OFF = [
    { id: 'E20', case: 'IP-literal site.host in Host',
      headers: { 'Host' => SITE_HOST }, proto: nil,
      idp: :platform, redirect_uri: "http://#{SITE_HOST}", link: "http://#{SITE_HOST}", brand: SITE_HOST },
    # The email link builds on site.host, but platform SSO is not started:
    # the tenant hook keys on display_domain, then the detected host, then
    # request.host (hooks/omniauth_tenant.rb, .public_host). display_domain
    # is canonical, DetectHost accepted nothing and Rack has no host, so the
    # hook is left without a host to recognise as the operator's.
    { id: 'E21', case: 'doubled IP-literal site.host',
      headers: { 'Host' => "#{SITE_HOST}, #{SITE_HOST}" }, proto: nil,
      changes_with: '#4223',
      idp: nil, sso_location: '/signin?auth_error=sso_not_configured',
      link: "http://#{SITE_HOST}", brand: SITE_HOST },
  ].freeze
end

RSpec.describe 'Host and proxy simulation matrix (#4223)', :shared_db_state, type: :integration do
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
  def with_site_host(host)
    return yield if host.nil?

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
    header 'X-Forwarded-Proto', 'https' unless row.key?(:proto) && row[:proto].nil?
    row[:headers].each { |name, value| header name, fill(value) }
  end

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

  shared_examples 'a request matrix' do |rows|
    rows.each do |row|
      suffix = row[:changes_with] ? " (current behaviour; #{row[:changes_with]})" : ''

      it "#{row[:id]} #{row[:case]}#{suffix}" do
        with_site_host(row[:site_host]) do
          prepare_record(row[:record])
          apply_topology(row)
          header 'Accept', 'application/json'
          get '/auth'

          actual   = observed
          expected = HostProxyMatrix::OBSERVED_KEYS.to_h { |key| [key, fill(row[key])] }

          expect(actual.slice(*HostProxyMatrix::OBSERVED_KEYS)).to eq(expected)
          # The redirect_uri and the emailed link read one chain.
          expect(actual[:email_origin]).to eq(actual[:origin])
          expect(actual[:rack_base_url]).to eq(fill(row[:rack_base_url])) if row.key?(:rack_base_url)
          # Whatever the row sent, no auth URL carries a comma.
          expect(actual[:origin]).not_to include(',')
        end
      end
    end
  end

  shared_examples 'an emitter matrix' do |rows|
    let(:account_email) { unique_test_email('matrix') }
    let!(:account_id) { seed_account_with_password(account_email) }

    # Both sign-in methods on, so the reset route is served on the tenant
    # domain (Auth::SigninGate) and tenant SSO stays enabled.
    before do
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: test_custom_domain.identifier,
        enabled: true,
        signin_enabled: true,
        sso_enabled: true,
      )

      unless Onetime.auth_config.orgs_sso_enabled?
        skip 'ORGS_SSO_ENABLED not set at boot — /auth/sso/* routes are not registered'
      end

      @delivered = []
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
        @delivered << email
        true
      end
    end

    after do
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
      # :shared_db_state skips the per-example auth database clear.
      clear_auth_database
    end

    def origin_of(url)
      uri     = URI.parse(url)
      default = uri.scheme == 'https' ? 443 : 80
      uri.port == default ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end

    rows.each do |row|
      suffix = row[:changes_with] ? " (current behaviour; #{row[:changes_with]})" : ''

      it "#{row[:id]} #{row[:case]}#{suffix}" do
        prepare_record(row[:record])
        apply_topology(row)

        # --- SSO -------------------------------------------------------------
        post '/auth/sso/entra'
        location = last_response.headers['Location'].to_s
        expect(last_response.status).to eq(302)

        if row[:idp]
          entra_tenant = row[:idp] == :tenant ? test_sso_config.tenant_id : 'placeholder'
          expect(location).to start_with("https://login.microsoftonline.com/#{entra_tenant}/")

          redirect_uri = CGI.parse(URI.parse(location).query.to_s)['redirect_uri'].first.to_s
          expect(redirect_uri).to eq("#{fill(row[:redirect_uri])}/auth/sso/entra/callback")
        else
          expect(location).to end_with(row[:sso_location])
        end

        # --- Email -----------------------------------------------------------
        clear_cookies
        csrf_json_post('/auth/reset-password-request', login: account_email)

        if row[:link].nil?
          expect(@delivered).to be_empty
          expect(last_response.status).to eq(row[:reset_status])
          next
        end

        expect(@delivered.size).to eq(1),
          "expected one delivered email, got #{@delivered.size}. " \
          "Last response: #{last_response.status} #{last_response.body.to_s[0, 300]}"
        email = @delivered.first
        link  = email[:body].to_s[%r{https?://[^\s,]+/reset-password\?key=\S+}]

        expect(link).not_to be_nil, "no reset link in the delivered body:\n#{email[:body].to_s[0, 600]}"
        expect(origin_of(link)).to eq(fill(row[:link]))
        expect(email[:subject].to_s).to include("(#{fill(row[:brand])})")
      end
    end
  end

  it 'runs with the forwarded-header family the stack pins' do
    expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
  end

  context 'with the domains feature on' do
    # features.domains.default = canonical.example.org; site.host stays the
    # IP literal from spec/config.test.yaml unless a row replaces it.
    include_context 'domains enabled'

    let(:matrix_canonical_host) { canonical_host }

    include_examples 'a request matrix', HostProxyMatrix::DOMAINS_ON
    include_examples 'an emitter matrix', HostProxyMatrix::EMITTERS_ON

    it 'installs the origin resolver as a per-request Proc' do
      # OmniAuth::Strategy#full_host calls it only when it is a Proc; a
      # String would fix one host for the whole process.
      expect(OmniAuth.config.full_host).to be_a(Proc)
    end
  end

  context 'with the domains feature off' do
    # The lanes run with the feature off, but say so here instead of
    # inheriting it: another file's 'domains enabled' context, or a shell
    # that exports DOMAINS_ENABLED, would otherwise change what these rows
    # mean. Same three switches that context moves, the other way.
    before(:all) do
      boot_onetime_app
      @matrix_saved_features = Onetime::Runtime.features
      @matrix_saved_domains  = OT.conf.dig('features', 'domains') || {}
    end

    before do
      OT.conf['features']['domains'] = @matrix_saved_domains.merge('enabled' => false, 'default' => nil)
      Onetime::Runtime.features      = Onetime::Runtime.features.with(domains_enabled: false)
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
    end

    after(:all) do
      Onetime::Runtime.features      = @matrix_saved_features if @matrix_saved_features
      OT.conf['features']['domains'] = @matrix_saved_domains
      Onetime::Middleware::DomainStrategy.initialize_from_config(@matrix_saved_domains)
    end

    # No row here uses the {canonical} placeholder for a second host: the
    # only canonical host is site.host.
    let(:matrix_canonical_host) { HostProxyMatrix::SITE_HOST }

    include_examples 'a request matrix', HostProxyMatrix::DOMAINS_OFF
    include_examples 'an emitter matrix', HostProxyMatrix::EMITTERS_OFF
  end

  # The resolver reads what DetectHost and DomainStrategy leave in the env.
  # These rows hand it an env the request rows above do not reach — the
  # mounted stack always writes both keys, and writes them consistently —
  # so they call the resolver directly, against the booted configuration.
  describe 'env states the request rows do not reach' do
    include_context 'domains enabled'

    let(:matrix_canonical_host) { canonical_host }
    let(:resolver) { Auth::Config::Features::OmniAuth }

    def bare_env(host:, scheme: 'https', **keys)
      Rack::MockRequest.env_for(
        "#{scheme}://#{host}/auth/sso/entra",
        'HTTP_HOST' => host,
        'HTTP_X_FORWARDED_PROTO' => scheme,
        **keys.transform_keys(&:to_s),
      )
    end

    it 'builds on configured site.host when neither middleware wrote its key' do
      env = bare_env(host: 'example.com')

      expect(resolver.full_host_for(env)).to eq(HostProxyMatrix::SITE_HOST_ORIGIN)
      expect(resolver.public_host_for(env)).to be_nil
    end

    it 'falls to the request authority only when site.host is unconfigured' do
      allow(Auth::PublicHost).to receive_messages(canonical_host: nil, canonical_base_url: nil)
      env = bare_env(host: 'example.com')

      expect(resolver.full_host_for(env)).to eq('https://example.com')
    end

    it 'treats a blank display domain as no tenant' do
      env = bare_env(host: canonical_host, 'onetime.display_domain' => '')

      expect(resolver.public_host_for(env)).to be_nil
    end

    it 'takes a verified display domain over a different detected host' do
      env = bare_env(
        host: canonical_host,
        'onetime.display_domain' => tenant_domain,
        Rack::DetectHost.result_field_name => HostProxyMatrix::UNREGISTERED,
      )

      expect(resolver.public_host_for(env)).to eq(tenant_domain)
      expect(resolver.full_host_for(env)).to eq("https://#{tenant_domain}")
    end

    # The resolver keys on the record, not the classification, so a verified
    # display domain is honoured whatever strategy accompanies it.
    it 'builds on a verified display domain that classified :invalid' do
      env = bare_env(
        host: canonical_host,
        'onetime.display_domain' => tenant_domain,
        'onetime.domain_strategy' => :invalid,
      )

      expect(resolver.full_host_for(env)).to eq("https://#{tenant_domain}")
    end
  end
end
