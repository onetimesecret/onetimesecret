# try/unit/boot/configure_domains_drift_try.rb
#
# frozen_string_literal: true

# Boot-time drift guard (#3841 follow-up): the ConfigureDomains initializer
# warns when features.domains.default names an ALREADY-REGISTERED custom
# domain. Requests to that host classify :canonical before the custom-domain
# lookup, so its per-domain brand/signin configuration silently never applies.
# Advisory only: the guard never changes classification and never fails boot.
# It runs once per boot (not once per mounted app) and checks the
# display_domain index via resolve_domain_id instead of hydrating the record.

require_relative '../../support/test_helpers'

OT.boot! :test, false

@initializer  = Onetime::Initializers::ConfigureDomains.new
@default_host = 'example-links.net'
@site_host    = 'example-app.com'

# Stub the index lookup: only the default host resolves to a domain id.
Onetime::CustomDomain.singleton_class.send(:alias_method, :orig_resolve_domain_id, :resolve_domain_id)
Onetime::CustomDomain.define_singleton_method(:resolve_domain_id) do |fqdn|
  fqdn == 'example-links.net' ? 'domain123' : nil
end

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

## Guard logs a loud error when default is a registered custom domain
captured = capture_le { @initializer.warn_if_default_shadows_custom_domain(@default_host, @site_host) }
captured.any? { |msg| msg.include?('registered custom domain') }
#=> true

## Guard stays silent when default is not a registered custom domain
captured = capture_le { @initializer.warn_if_default_shadows_custom_domain('unregistered.example.org', @site_host) }
captured.empty?
#=> true

## Guard stays silent when default equals site.host
captured = capture_le { @initializer.warn_if_default_shadows_custom_domain(@default_host, @default_host) }
captured.empty?
#=> true

## Guard stays silent when default is unset
captured = capture_le { @initializer.warn_if_default_shadows_custom_domain(nil, @site_host) }
captured.empty?
#=> true

## Lookup raising does not crash boot
Onetime::CustomDomain.define_singleton_method(:resolve_domain_id) do |_fqdn|
  raise StandardError, 'redis unavailable'
end
result = begin
  @initializer.warn_if_default_shadows_custom_domain(@default_host, @site_host)
  :no_raise
rescue StandardError
  :raised
end
result
#=> :no_raise

# Teardown
Onetime::CustomDomain.singleton_class.send(:alias_method, :resolve_domain_id, :orig_resolve_domain_id)
Onetime::CustomDomain.singleton_class.send(:remove_method, :orig_resolve_domain_id)
