# try/integration/middleware/domain_strategy/multiple_canonical_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@canonical_domain = 'eu.example.com'
@parser = Onetime::Middleware::DomainStrategy::Parser
@chooser = Onetime::Middleware::DomainStrategy::Chooserator
@strategy_class = Onetime::Middleware::DomainStrategy

# Split-deployment canonical set: site.host serves the app while
# features.domains.default anchors generated links (different apexes).
@site_host    = 'example-app.com'
@default_host = 'example-links.net'
@site_host_orig = OT.conf['site']['host']

# Helper to create a minimal Rack app
def create_app
  ->(env) { [200, {}, ['OK']] }
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
config = { 'enabled' => true, 'default' => @default_host }
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
config = { 'enabled' => true, 'default' => nil }
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
config = { 'enabled' => true, 'default' => @default_host }
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

# Implicit Override Consistency Tests (dev-only domain context feature)

## Request to site.host is NOT an implicit override when default differs
middleware = @strategy_class.new(create_app)
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env = { Rack::DetectHost.result_field_name => @site_host }
middleware.detect_domain_override(env)
#=> [nil, nil]

## Request to default host is NOT an implicit override either
middleware = @strategy_class.new(create_app)
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env = { Rack::DetectHost.result_field_name => @default_host }
middleware.detect_domain_override(env)
#=> [nil, nil]

## Request outside the canonical set is still an implicit override
middleware = @strategy_class.new(create_app)
OT.conf['site']['host'] = @site_host
@strategy_class.initialize_from_config({ 'enabled' => true, 'default' => @default_host })
@strategy_class.class_eval { @domain_context_enabled = true }
env = { Rack::DetectHost.result_field_name => 'custom.example.org' }
middleware.detect_domain_override(env)
#=> ['custom.example.org', :detected_host]

# Drift guard (features.domains.default names a registered custom domain)
# lives in the ConfigureDomains initializer so it runs once per boot, not
# once per mounted app. See try/unit/boot/configure_domains_drift_try.rb.

# Teardown
OT.conf['site']['host'] = @site_host_orig
@strategy_class.reset!
