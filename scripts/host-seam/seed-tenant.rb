#!/usr/bin/env ruby
# scripts/host-seam/seed-tenant.rb
#
# Seeds the ONE fixture the host-seam matrix needs: a custom domain owned by an
# organization, with an enabled tenant SSO config. Without it the SSO column of
# topology-probe.sh reads NO_CONFIG everywhere and cannot distinguish "the seam
# is broken" from "nothing was ever configured".
#
# Mirrors apps/web/auth/spec/support/tenant_test_fixtures.rb, minus the
# per-example teardown — the sweep wants the fixture to persist for the life of
# the datastore.
#
# It is deliberately IDEMPOTENT: re-running against a seeded datastore reuses
# the existing records instead of stacking duplicates, so the sweep can seed
# once and reuse across releases (which additionally surfaces model/index drift
# — an older release failing to read a newer release's records is itself a
# finding worth seeing).
#
# Run inside the app (container or checkout):
#   HOST_SEAM_DOMAIN=local-secrets1.afb.pet bin/ots console < scripts/host-seam/seed-tenant.rb
#
# Or directly, if the app is already booted in-process:
#   bundle exec ruby -r./lib/onetime scripts/host-seam/seed-tenant.rb
#
# Env:
#   HOST_SEAM_DOMAIN     custom domain to register  (default local-secrets1.afb.pet)
#   HOST_SEAM_TENANT_ID  Entra tenant id to inject  (default host-seam-tenant)
#
# The tenant id is what proves TENANT credentials were injected rather than the
# platform fallback: it lands in the authorize URL path, which the probe reads.
# client_id is a concealed field and cannot be asserted on.

domain_name = ENV.fetch('HOST_SEAM_DOMAIN', 'local-secrets1.afb.pet')
tenant_id   = ENV.fetch('HOST_SEAM_TENANT_ID', 'host-seam-tenant')

abort 'FATAL: app not booted — run this through `bin/ots console`' unless defined?(Onetime)

# --- Organization ----------------------------------------------------------
owner_email = "host-seam-owner@#{domain_name}"

existing = Onetime::CustomDomain.from_display_domain(domain_name)

if existing
  warn "reusing existing CustomDomain #{domain_name} (#{existing.identifier})"
  domain = existing
else
  owner = Onetime::Customer.new(email: owner_email)
  owner.save
  org   = Onetime::Organization.create!('Host Seam Matrix Org', owner, owner_email)

  domain = Onetime::CustomDomain.new(display_domain: domain_name, org_id: org.org_id)
  domain.save
  Onetime::CustomDomain.display_domain_index.put(domain_name, domain.domainid)
  warn "created CustomDomain #{domain_name} (#{domain.identifier}) for org #{org.org_id}"
end

# --- SSO config ------------------------------------------------------------
# Credentials are fake on purpose. The probe never completes an OAuth round
# trip; it only reads the authorize URL the app builds, which is enough to tell
# tenant credentials from the platform fallback.
existing_sso = begin
  Onetime::CustomDomain::SsoConfig.for_domain(domain.identifier)
rescue StandardError
  nil
end

if existing_sso
  warn "reusing existing SsoConfig for #{domain_name}"
else
  Onetime::CustomDomain::SsoConfig.create!(
    domain_id: domain.identifier,
    provider_type: 'entra_id',
    display_name: 'Host Seam Matrix IdP',
    tenant_id: tenant_id,
    client_id: 'host-seam-client',
    client_secret: 'host-seam-secret',
    enabled: true,
  )
  warn "created SsoConfig for #{domain_name} (tenant_id=#{tenant_id})"
end

warn "SEEDED domain=#{domain_name} tenant_id=#{tenant_id}"
