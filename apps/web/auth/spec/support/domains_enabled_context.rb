# apps/web/auth/spec/support/domains_enabled_context.rb
#
# frozen_string_literal: true

# =============================================================================
# SHARED CONTEXT: 'domains enabled'
# =============================================================================
#
# Declares that a spec needs the custom-domain axis ON, so the classification
# a Host header receives is a property of the FILE and not of the shell the
# suite happened to run in.
#
#   include_context 'domains enabled'
#   include_context 'domains enabled', 'operator-signin-gate.example.com'
#
# Inside the group, `canonical_host` is the operator host that was installed.
#
# ---------------------------------------------------------------------------
# WHY A SPEC HAS TO DECLARE THIS AT ALL
# ---------------------------------------------------------------------------
#
# `features.domains.enabled` in spec/config.test.yaml reads DOMAINS_ENABLED,
# an AMBIENT env var: direnv sets it in dev shells, the hermetic lanes scrub
# it. A spec that quietly needs one setting or the other is green in whichever
# shell its author used and red in the other, which is how this tree ended up
# with two disjoint failing sets — 9 files that needed the flag ON and 24
# examples that needed a parseable canonical host. Neither set said so.
#
# Two INDEPENDENT switches have to move together, and moving only one is worse
# than moving neither:
#
#   1. Onetime::Runtime.features.domains? — what DomainStrategy#call reads
#      (domain_strategy.rb:324) to decide whether to classify the request host
#      at all. With it OFF the middleware short-circuits: EVERY request is
#      :canonical and env['onetime.display_domain'] IS the canonical host, so
#      tenant-host assertions compare against site.host and custom-domain
#      branches are never taken — the spec passes vacuously or fails with
#      `got: "127.0.0.1"`.
#
#   2. A PARSEABLE canonical host. The test config's site.host is
#      `127.0.0.1:3000`; PublicSuffix cannot parse an IP literal, so
#      initialize_from_config's `Parser.parse(canonical_domain)` raises,
#      the parsed canonical set comes out EMPTY, and Chooserator returns nil
#      for every host it is handed — including the canonical one. :invalid is
#      not an operator host
#      (ADR-024#operator-defaults-require-positive-classification), so the
#      tenant-safe default-OFF branch applies and Auth::SigninEnabled answers
#      404 on routes that have nothing to do with domains. Flipping switch 1
#      WITHOUT switch 2 is what produces that state: the instance-level
#      `domains_enabled?` reads Runtime.features (now true) while the canonical
#      SET was derived with enabled=false and an unparseable site.host.
#
# ---------------------------------------------------------------------------
# WHY IT EDITS OT.conf AND NOT ONLY THE CLASS STATE
# ---------------------------------------------------------------------------
#
# DomainStrategy keeps the canonical set in CLASS-level state, and
# DomainStrategy#initialize (domain_strategy.rb:185) re-runs
# initialize_from_config against OT.conf on EVERY instantiation. Any rebuild
# of the mounted stack therefore reverts a class-state-only assignment to
# whatever the config says — and rebuilds happen on their own schedule: the
# before(:all) reboots several files in this tree perform drop the memoized
# mount (Registry.rack_url_map), which is then rebuilt lazily on the next
# example's first request, i.e. AFTER that example's before hooks. Writing
# the config the middleware re-reads is what
# makes the override survive a rebuild instead of racing it. The alternative
# (stubbing initialize_from_config to freeze the class state) only lasts as
# long as the mock, i.e. one example, and hides the config from every other
# reader of features.domains.default (Onetime::Utils::CanonicalHosts and
# friends).
#
# The per-example `before` below then closes the remaining gap in the other
# direction: with the mount memoized, NOTHING re-instantiates the middleware
# between examples, so an in-place OT.conf edit alone would never reach the
# class state. Applying both — the config and initialize_from_config — is what
# makes this context correct whether or not a rebuild happens to intervene.
#
# ---------------------------------------------------------------------------
# WHY A SYNTHETIC HOST AND NOT site.host
# ---------------------------------------------------------------------------
#
# Same trick bin/visual uses (DEFAULT_DOMAIN=canonical.example.org): give the
# classifier a real hostname to match. `features.domains.default` becomes the
# PRIMARY canonical host (#3841), so the unparseable site.host is demoted to a
# skipped set member instead of the entry that disables the whole feature.
#
# Pass a custom host when the file's own fixture hosts need to sit in a
# specific relationship to it (see signin_enabled_enforcement_spec.rb, whose
# tenant hosts are peers under example.com). Otherwise take the default: it is
# the same host spec/config.test.yaml installs when DOMAINS_ENABLED=true, so
# opting in changes classification for the file's fixture hosts and nothing
# else.
#
# ---------------------------------------------------------------------------
# RESTORATION
# ---------------------------------------------------------------------------
#
# Runtime.features, OT.conf['features']['domains'] and the DomainStrategy
# class state are all process-global and shared with every other file in the
# run. The originals are captured once in before(:all) and put back in
# after(:all); the axis itself is re-asserted per example (see the hook), so a
# group that reboots the app mid-file cannot silently drop it. The env var is
# deliberately NOT touched: the lane env is shared, and a spec that mutated it
# would leak into files that never opted in.
#
module DomainsEnabledContext
  # An operator host PublicSuffix can parse, kept identical to the default
  # spec/config.test.yaml installs for DOMAINS_ENABLED=true so a file behaves
  # the same whether it opted in or inherited the ambient setting.
  #
  # `.example.org` is chosen against the fixture hosts in this tree, which are
  # uniformly `*.example.com`: no fixture is a peer, parent or subdomain of it,
  # so none of them can accidentally sweep to :canonical.
  CANONICAL_HOST = 'canonical.example.org'
end

RSpec.shared_context 'domains enabled' do |host = DomainsEnabledContext::CANONICAL_HOST|
  # Captured lexically: `host` is a block parameter of the shared context, not
  # visible inside the instance_exec'd hooks below without this binding.
  installed_canonical_host = host

  before(:all) do
    # Idempotent, and required here rather than assumed: this hook may run
    # before the including group's own before(:all), and OT.conf does not
    # exist until the app has booted.
    boot_onetime_app

    @domains_context_saved_features = Onetime::Runtime.features
    @domains_context_saved_config   = OT.conf.dig('features', 'domains') || {}
  end

  # Re-assert per example, not only once per group.
  #
  # Several files in this tree call `Onetime.boot!(:test, force: true)` in
  # their OWN before(:all) to re-register OmniAuth providers. A forced boot
  # reloads OT.conf from disk and rebuilds Onetime::Runtime.features, so
  # whichever of the two before(:all) hooks runs second wins — and hook order
  # is declaration order, i.e. it depends on where `include_context` was
  # typed in the file. Re-applying here makes the axis hold regardless, and it
  # is cheap: a hash merge plus a config re-read of a handful of hosts.
  before do
    OT.conf['features']['domains'] = @domains_context_saved_config.merge(
      'enabled' => true,
      'default' => installed_canonical_host,
    )
    Onetime::Runtime.features = Onetime::Runtime.features.with(domains_enabled: true)
    Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
  end

  after(:all) do
    Onetime::Runtime.features = @domains_context_saved_features if @domains_context_saved_features

    next unless @domains_context_saved_config

    OT.conf['features']['domains'] = @domains_context_saved_config
    Onetime::Middleware::DomainStrategy.initialize_from_config(@domains_context_saved_config)
  end

  # The operator host installed above. Requests carrying it classify
  # :canonical; anything else the file registers as a CustomDomain classifies
  # :custom.
  let(:canonical_host) { installed_canonical_host }
end
