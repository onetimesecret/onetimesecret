# try/integration/middleware/domain_strategy/multiple_canonical_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@canonical_domain = 'eu.example.com'
@parser           = Onetime::Middleware::DomainStrategy::Parser
@chooser          = Onetime::Middleware::DomainStrategy::Chooserator
@strategy_class   = Onetime::Middleware::DomainStrategy

# Split-deployment canonical set: site.host serves the app while
# features.domains.default anchors generated links (different apexes).
@site_host      = 'example-app.com'
@default_host   = 'example-links.net'
@site_host_orig = OT.conf['site']['host']

# #4063 fixtures. @internal_host mirrors the motivating install: an
# internal platform address that must keep SERVING while being hidden
# from the customer-facing link picker. @pool_host shares no base domain
# with any canonical anchor, so it can only classify :canonical by being
# a canonical-set member -- never via the subdomain/peer sweeps.
@internal_host = 'ge-abcd123.eu.otshosted.com'
@pool_host     = 'go.acme.com'
@short_host    = 'short.example.com'

# Helper to create a minimal Rack app
def create_app
  ->(_env) { [200, {}, ['OK']] }
end

# Captures OT.le output for the duration of the block. Copied from
# try/unit/boot/configure_domains_drift_try.rb:27-38 -- the unparseable
# canonical-host skip is logged at error level precisely so it is
# observable here.
def capture_le
  captured = []
  Onetime.singleton_class.send(:alias_method, :orig_le, :le)
  Onetime.define_singleton_method(:le) { |*msgs, **_kw| captured.concat(msgs) }
  begin
    yield
  ensure
    Onetime.singleton_class.send(:alias_method, :le, :orig_le)
    Onetime.singleton_class.send(:remove_method, :orig_le)
  end
  captured
end

# Enables the domains feature at the RUNTIME level for the duration of the
# block, then restores it. DomainStrategy#call short-circuits to :canonical
# unless Onetime::Runtime.features.domains? is true, so the end-to-end
# wiring cases need it. Same idiom as
# try/integration/middleware/domain_strategy/response_headers_try.rb:29-31.
def with_runtime_domains
  original                  = Onetime::Runtime.features
  Onetime::Runtime.features = original.with(domains_enabled: true)
  yield
ensure
  Onetime::Runtime.features = original
end

# Domain Validation Tests
## Valid canonical domain passes validation
@chooser.choose_strategy(@canonical_domain, @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', @canonical_domain)
#=> :canonical

## Domain with consecutive dots fails validation
@chooser.choose_strategy('us.example.com', @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', 'example.com')
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('eu.example.com', 'example.com')
#=> :subdomain

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', 'eu.example.com')
#=> :canonical

# Canonical Set Tests (choose_strategy with a list of hosts)

## Empty canonical set returns nil (same guard as nil single host)
@chooser.choose_strategy('example.com', [])
#=> nil

## Request to site.host classifies :canonical
@chooser.choose_strategy(@site_host, [@default_host, @site_host])
#=> :canonical

## Request to default host classifies :canonical
@chooser.choose_strategy(@default_host, [@default_host, @site_host])
#=> :canonical

## Subdomain of site.host classifies :subdomain
@chooser.choose_strategy('sub.example-app.com', [@default_host, @site_host])
#=> :subdomain

## Subdomain of default host classifies :subdomain
@chooser.choose_strategy('sub.example-links.net', [@default_host, @site_host])
#=> :subdomain

## :canonical beats :subdomain when hosts disagree for one request
@chooser.choose_strategy('eu.example.com', ['eu.example.com', 'example.com'])
#=> :canonical

# Class Configuration Tests (canonical set built from site.host + default)

## Split deployment: both hosts land in the canonical set, default first
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host }
@strategy_class.initialize_from_config(config)
@strategy_class.canonical_domains
#=> ['example-links.net', 'example-app.com']

## canonical_domain reader still returns the primary display host (default)
@strategy_class.canonical_domain
#=> 'example-links.net'

## Request to site.host classifies :canonical via the parsed set
@chooser.choose_strategy(@site_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## Request to default classifies :canonical via the parsed set
@chooser.choose_strategy(@default_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## Subdomain of site.host classifies :subdomain via the parsed set
@chooser.choose_strategy('sub.example-app.com', @strategy_class.canonical_domains_parsed)
#=> :subdomain

## Class-level canonical_host? treats site.host as canonical
@strategy_class.canonical_host?(@site_host)
#=> true

## Class-level canonical_host? treats the default host as canonical
@strategy_class.canonical_host?(@default_host)
#=> true

## Class-level canonical_host? normalizes case and port
@strategy_class.canonical_host?('EXAMPLE-APP.COM:443')
#=> true

## Class-level canonical_host? rejects subdomains of canonical hosts
@strategy_class.canonical_host?('sub.example-app.com')
#=> false

## Class-level canonical_host? rejects hosts outside the set
@strategy_class.canonical_host?('custom.example.org')
#=> false

## Default unset: behavior identical to today (site.host is sole canonical)
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => nil }
@strategy_class.initialize_from_config(config)
[@strategy_class.canonical_domain, @strategy_class.canonical_domains]
#=> ['example-app.com', ['example-app.com']]

## Default unset: site.host classifies :canonical
@chooser.choose_strategy(@site_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## Default unset: subdomain of site.host classifies :subdomain
@chooser.choose_strategy('sub.example-app.com', @strategy_class.canonical_domains_parsed)
#=> :subdomain

## Unparseable site.host (IP literal) is skipped from the parsed set
@strategy_class.reset!
OT.conf['site']['host'] = '127.0.0.1:3000'
config                  = { 'enabled' => true, 'default' => @default_host }
@strategy_class.initialize_from_config(config)
@strategy_class.canonical_domains_parsed.map(&:name)
#=> ['example-links.net']

## Unparseable host in the canonical set does not poison exact matches
@chooser.choose_strategy('example-links.net', ['127.0.0.1:3000', 'example-links.net'])
#=> :canonical

## Canonical set with only unparseable hosts classifies nil (:invalid)
@chooser.choose_strategy('example-links.net', ['127.0.0.1:3000'])
#=> nil

## Re-init with an unparseable primary disables domains and clears the parsed set
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => '127.0.0.1:3000' })
[@strategy_class.domains_enabled?, @strategy_class.canonical_domains_parsed]
#=> [false, []]

## Re-init that disables domains clears the parsed set (no stale fallback)
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.initialize_from_config({ 'enabled' => false })
[@strategy_class.domains_enabled?, @strategy_class.canonical_domains_parsed]
#=> [false, []]

# Custom-Domain Shadowing Tests (#3841 follow-up)
#
# A REGISTERED custom domain that falls under a canonical host's base
# domain must keep :custom — the subdomain/peer sweeps across the
# canonical set run only for unregistered hosts. Brand/signin config is
# gated on :custom, so a :subdomain or :canonical reclassification would
# silently drop it.

## Registered custom domain under site.host's base domain stays :custom
Onetime::CustomDomain.singleton_class.send(:alias_method, :shadow_orig_from_display_domain, :from_display_domain)
Onetime::CustomDomain.define_singleton_method(:from_display_domain) do |domain|
  %w[secrets.example-app.com secrets.example.com example-app.com].include?(domain) ? Object.new : nil
end
@chooser.choose_strategy('secrets.example-app.com', [@default_host, @site_host])
#=> :custom

## Unregistered subdomain of site.host still classifies :subdomain
@chooser.choose_strategy('other.example-app.com', [@default_host, @site_host])
#=> :subdomain

## Registered custom domain that peers a canonical subdomain host stays :custom
@chooser.choose_strategy('secrets.example.com', ['eu.example.com'])
#=> :custom

## Unregistered peer of a canonical subdomain host still classifies :canonical
@chooser.choose_strategy('other.example.com', ['eu.example.com'])
#=> :canonical

## Exact canonical-set match beats an identical custom-domain registration
@chooser.choose_strategy('example-app.com', [@default_host, @site_host])
#=> :canonical

## Restoring the real lookup returns the sweeps to normal
Onetime::CustomDomain.singleton_class.send(:alias_method, :from_display_domain, :shadow_orig_from_display_domain)
Onetime::CustomDomain.singleton_class.send(:remove_method, :shadow_orig_from_display_domain)
@chooser.choose_strategy('unregistered.example-app.com', [@default_host, @site_host])
#=> :subdomain

# Operator Link Pool Tests (#4063 features.domains.link_domains)
#
# One setting, two derived sets. Every link domain JOINS the canonical
# host set (classification/admission), while the picker reads the pool
# separately. That split is what lets an internal canonical host keep
# serving while being hidden from the customer-facing picker.
#
# These cases follow the file's idiom: an explicit config hash into
# initialize_from_config plus direct OT.conf['site']['host'] mutation,
# never a stub. Each block resets class state first; teardown restores
# site.host and calls reset! (which nils @link_domains too).

## AC3: an unrelated-base-domain link host joins the canonical set, appended after both anchors
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] }
@strategy_class.initialize_from_config(config)
@strategy_class.canonical_domains
#=> ['example-links.net', 'example-app.com', 'go.acme.com']

## AC3: the primary is unchanged by the appended pool member
@strategy_class.canonical_domain
#=> 'example-links.net'

## AC3: the link host survives into the parsed set used for classification
@strategy_class.canonical_domains_parsed.map(&:name)
#=> ['example-links.net', 'example-app.com', 'go.acme.com']

## AC3: a request to the link host classifies :canonical, not nil (:invalid)
@chooser.choose_strategy(@pool_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## AC8: canonical_host? agrees with the :canonical classification for the link host
@strategy_class.canonical_host?(@pool_host)
#=> true

## AC8: canonical_host? and classification BOTH track EXACT pool membership
# T11 recorded the opposite here (a swept :canonical) as a consequence of
# pool membership rather than a blessing; T16 removed the widening. A pool
# member joins the canonical set for EXACT matching only -- the
# peer/parent and subdomain sweeps iterate the ANCHOR hosts. The operator
# blessed go.acme.com, not acme.com, so an unregistered sibling on that
# shared base domain classifies nil (:invalid), matching what
# canonical_host? -- the admission predicate used by
# Account::UpdateDomainContext -- already said.
[@strategy_class.canonical_host?('other.acme.com'),
 @chooser.choose_strategy(
   'other.acme.com',
   @strategy_class.canonical_domains_parsed,
   anchor_domains: @strategy_class.anchor_domains_parsed,
 )]
#=> [false, nil]

# T17: the `www.` variant tolerance is ANCHOR-only
#
# equal_to? matches a host against `www.<registrable-domain>` as well as
# against its own name. Run over the FULL canonical set that second arm
# reaches straight past the pool member the operator blessed and onto any
# `www.` sibling on the same base domain -- the same widening the
# anchor-only sweeps exist to prevent, arriving through the exact-match
# arm instead. Worse than the sweep case: this arm runs BEFORE
# known_custom_domain?, so it takes the classification away from a tenant
# who registered that host, silently dropping their brand/signin config.
#
# The fix splits the arm: exact_host? over the full set (pool included),
# equal_to? over the anchors only.

## T17: `www.` of a POOL member's base domain is not :canonical
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] }
@strategy_class.initialize_from_config(config)
@chooser.choose_strategy(
  'www.acme.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> nil

## T17: and a tenant who REGISTERED that host keeps :custom
# This is the consequence that matters. Under the old arm the www variant
# classified :canonical ahead of the registration lookup, so the tenant's
# per-domain configuration silently never applied.
Onetime::CustomDomain.singleton_class.send(:alias_method, :www_orig_from_display_domain, :from_display_domain)
Onetime::CustomDomain.define_singleton_method(:from_display_domain) do |domain|
  domain == 'www.acme.com' ? Object.new : nil
end
result = @chooser.choose_strategy(
  'www.acme.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
Onetime::CustomDomain.singleton_class.send(:alias_method, :from_display_domain, :www_orig_from_display_domain)
Onetime::CustomDomain.singleton_class.send(:remove_method, :www_orig_from_display_domain)
result
#=> :custom

## T17 control: `www.` of an ANCHOR host is still :canonical
# The tolerance itself is untouched -- it just no longer reaches the pool.
@chooser.choose_strategy(
  "www.#{@site_host}",
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> :canonical

## T17 control: `www.` of the OTHER anchor is :canonical too
@chooser.choose_strategy(
  "www.#{@default_host}",
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> :canonical

## T17: `www.` of the pool member itself gets nothing either
# The operator blessed go.acme.com. www.go.acme.com is a different host.
@chooser.choose_strategy(
  "www.#{@pool_host}",
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> nil

## T17 fence: with no pool the two sets are equal and nothing changes
# anchor_domains defaults to the canonical set, so a caller with no pool
# (every pre-#4063 call site) sees the exact pre-#4063 answers.
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
[@chooser.choose_strategy("www.#{@site_host}", @strategy_class.canonical_domains_parsed),
 @chooser.choose_strategy("www.#{@default_host}", @strategy_class.canonical_domains_parsed)]
#=> [:canonical, :canonical]

## T17 wiring: the middleware call path rejects the pool-adjacent www host
# Guards the real request path, not just Chooserator.
middleware                                           = @strategy_class.new(create_app)
@strategy_class.reset!
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config(
  { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] },
)
@strategy_class.class_eval { @domain_context_enabled = false }
env                                                  = { Rack::DetectHost.result_field_name => 'www.acme.com' }
with_runtime_domains { middleware.call(env) }
env['onetime.domain_strategy']
#=> :invalid

# T16: exact-match set vs. sweep set
#
# Two sets come out of initialize_from_config. canonical_domains_parsed is
# the EXACT-match set (anchors + pool). anchor_domains_parsed is the
# subset the peer/parent and subdomain sweeps iterate (site.host +
# features.domains.default). CustomDomain.overlaps_canonical_domain? makes
# the same split -- exact arm over the full set, base-domain arm over
# anchors only -- and the two must keep agreeing.

## T16: the anchor set is the pre-#4063 two-element set, pool member excluded
@strategy_class.anchor_domains_parsed.map(&:name)
#=> ['example-links.net', 'example-app.com']

## T16: the pool member itself still classifies :canonical, via the exact-match arm
@chooser.choose_strategy(
  @pool_host,
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> :canonical

## T16: the PARENT of a pool member is not swept in either (parent_of? is anchor-only)
@chooser.choose_strategy(
  'acme.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> nil

## T16: an unregistered subdomain of an ANCHOR host still classifies :subdomain
@chooser.choose_strategy(
  'sub.example-app.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
#=> :subdomain

## T16 asymmetry: an anchor's unregistered peer is :canonical, a pool member's is not
# @internal_host is subdomain-shaped, so peer_of? applies to it -- this is
# the pre-#4063 sweep behavior for anchors, untouched. The pool member
# @pool_host is subdomain-shaped too, and its peer gets nothing. Same
# request shape, opposite answer: that asymmetry is the whole point.
@strategy_class.reset!
OT.conf['site']['host'] = @internal_host
config                  = { 'enabled' => true, 'default' => nil, 'link_domains' => [@pool_host] }
@strategy_class.initialize_from_config(config)
[@chooser.choose_strategy(
  'other.eu.otshosted.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
),
 @chooser.choose_strategy(
   'other.acme.com',
   @strategy_class.canonical_domains_parsed,
   anchor_domains: @strategy_class.anchor_domains_parsed,
 )]
#=> [:canonical, nil]

## T16: the anchor set follows site.host when features.domains.default is unset
@strategy_class.anchor_domains_parsed.map(&:name)
#=> ['ge-abcd123.eu.otshosted.com']

## T16 wiring: the middleware call path passes the anchor set to the sweeps
# Guards the call site itself, not just Chooserator: dropping the
# anchor_domains: kwarg in domain_strategy.rb#call would re-widen every
# real request while every direct-Chooserator case above stayed green.
middleware                                           = @strategy_class.new(create_app)
@strategy_class.reset!
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config(
  { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] },
)
@strategy_class.class_eval { @domain_context_enabled = false }
env                                                  = { Rack::DetectHost.result_field_name => 'other.acme.com' }
with_runtime_domains { middleware.call(env) }
env['onetime.domain_strategy']
#=> :invalid

## T16 wiring control: the blessed pool host still serves :canonical through call
middleware                                           = @strategy_class.new(create_app)
@strategy_class.reset!
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config(
  { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] },
)
@strategy_class.class_eval { @domain_context_enabled = false }
env                                                  = { Rack::DetectHost.result_field_name => @pool_host }
with_runtime_domains { middleware.call(env) }
[env['onetime.display_domain'], env['onetime.domain_strategy']]
#=> ['go.acme.com', :canonical]

## AC1 fence: link_domains unset resolves the pool to [canonical_domain] (pre-#4063 behavior)
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
[@strategy_class.canonical_domains, @strategy_class.link_domains]
#=> [['example-links.net', 'example-app.com'], ['example-links.net']]

## AC2 (serving half): the canonical host keeps serving while absent from the pool
# The picker half of AC2 is covered in
# src/tests/composables/useDomainContext.spec.ts ('operator link pool'):
# availableDomains must be exactly the pool, canonical absent.
@strategy_class.reset!
OT.conf['site']['host'] = @internal_host
config                  = { 'enabled' => true, 'default' => nil, 'link_domains' => [@short_host] }
@strategy_class.initialize_from_config(config)
[@chooser.choose_strategy(@internal_host, @strategy_class.canonical_domains_parsed),
 @strategy_class.canonical_domain,
 @strategy_class.link_domains]
#=> [:canonical, 'ge-abcd123.eu.otshosted.com', ['short.example.com']]

## AC2 (serving half): canonical_host? still true for the pool-excluded canonical host
@strategy_class.canonical_host?(@internal_host)
#=> true

## AC2 (serving half): the pool member serves :canonical alongside it
[@chooser.choose_strategy(@short_host, @strategy_class.canonical_domains_parsed),
 @strategy_class.canonical_host?(@short_host)]
#=> [:canonical, true]

# AC4 (security property): a tenant that registers a CustomDomain matching
# an operator pool entry must NOT be able to flip it to :custom -- the
# exact canonical-set arm outranks known_custom_domain?. Otherwise a
# tenant registration would capture an operator link domain and apply its
# own brand/signin config to it.
#
# The stub is proven LIVE by the control case below: the same registered
# host, absent from the canonical set, DOES classify :custom. Without
# that control a dead stub makes the AC4 case pass vacuously.

## AC4 control: the registration stub is live -- registered host outside the canonical set is :custom
Onetime::CustomDomain.singleton_class.send(:alias_method, :pool_orig_from_display_domain, :from_display_domain)
Onetime::CustomDomain.define_singleton_method(:from_display_domain) do |domain|
  domain == 'go.acme.com' ? Object.new : nil
end
@chooser.choose_strategy(@pool_host, [@default_host, @site_host])
#=> :custom

## AC4: the same registration does NOT flip a pool member away from :canonical
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] }
@strategy_class.initialize_from_config(config)
@chooser.choose_strategy(@pool_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## AC4: restoring the real lookup drops the host back out of the custom set
Onetime::CustomDomain.singleton_class.send(:alias_method, :from_display_domain, :pool_orig_from_display_domain)
Onetime::CustomDomain.singleton_class.send(:remove_method, :pool_orig_from_display_domain)
@chooser.choose_strategy(@pool_host, [@default_host, @site_host])
#=> nil

## T16: a REGISTERED sibling of a pool member still classifies :custom
# known_custom_domain? runs BEFORE the sweeps, so narrowing them to the
# anchors cannot take a customer's registered domain away from :custom.
# Without the registration this host would be nil (:invalid) -- see the
# 'other.acme.com' case above.
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] }
@strategy_class.initialize_from_config(config)
Onetime::CustomDomain.singleton_class.send(:alias_method, :sibling_orig_from_display_domain, :from_display_domain)
Onetime::CustomDomain.define_singleton_method(:from_display_domain) do |domain|
  domain == 'sibling.acme.com' ? Object.new : nil
end
result = @chooser.choose_strategy(
  'sibling.acme.com',
  @strategy_class.canonical_domains_parsed,
  anchor_domains: @strategy_class.anchor_domains_parsed,
)
Onetime::CustomDomain.singleton_class.send(:alias_method, :from_display_domain, :sibling_orig_from_display_domain)
Onetime::CustomDomain.singleton_class.send(:remove_method, :sibling_orig_from_display_domain)
result
#=> :custom

## AC7 control: a fully parseable pool logs no skip line (capture_le is discriminating)
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host] }
capture_le { @strategy_class.initialize_from_config(config) }
#=> []

## AC7: one unparseable pool entry is skipped and named in the error log
@strategy_class.reset!
OT.conf['site']['host'] = @site_host
config                  = { 'enabled' => true, 'default' => @default_host, 'link_domains' => [@pool_host, '999'] }
captured                = capture_le { @strategy_class.initialize_from_config(config) }
captured.any? { |msg| msg.include?('skipping unparseable canonical host') && msg.include?('999') }
#=> true

## AC7: a per-host skip is not a feature-level failure -- domains stay enabled
@strategy_class.domains_enabled?
#=> true

## AC7: only parseable entries survive into the parsed set
@strategy_class.canonical_domains_parsed.map(&:name)
#=> ['example-links.net', 'example-app.com', 'go.acme.com']

## AC7: the parseable pool member still classifies :canonical
@chooser.choose_strategy(@pool_host, @strategy_class.canonical_domains_parsed)
#=> :canonical

## AC7: the resolved pool drops the unparseable entry (offer only what we serve)
@strategy_class.link_domains
#=> ['go.acme.com']

## AC8: canonical_host? rejects the unparseable entry the classifier also rejects
[@strategy_class.canonical_host?('999'),
 @chooser.choose_strategy('999', @strategy_class.canonical_domains_parsed)]
#=> [false, nil]

# Implicit Override Consistency Tests (dev-only domain context feature)

## Request to site.host is NOT an implicit override when default differs
middleware                                           = @strategy_class.new(create_app)
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env                                                  = { Rack::DetectHost.result_field_name => @site_host }
middleware.detect_domain_override(env)
#=> [nil, nil]

## Request to default host is NOT an implicit override either
middleware                                           = @strategy_class.new(create_app)
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env                                                  = { Rack::DetectHost.result_field_name => @default_host }
middleware.detect_domain_override(env)
#=> [nil, nil]

## Request outside the canonical set is still an implicit override
middleware                                           = @strategy_class.new(create_app)
OT.conf['site']['host']                              = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env                                                  = { Rack::DetectHost.result_field_name => 'custom.example.org' }
middleware.detect_domain_override(env)
#=> ['custom.example.org', :detected_host]

# Drift guard (features.domains.default names a registered custom domain)
# lives in the ConfigureDomains initializer so it runs once per boot, not
# once per mounted app. See try/unit/boot/configure_domains_drift_try.rb.

# Teardown
OT.conf['site']['host'] = @site_host_orig
@strategy_class.reset!
