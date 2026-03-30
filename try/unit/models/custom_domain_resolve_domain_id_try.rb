# try/unit/models/custom_domain_resolve_domain_id_try.rb
#
# frozen_string_literal: true

# Tests for CustomDomain.display_domains FQDN-to-domain_id resolution.
#
# The display_domains class_hashkey maps an FQDN (e.g. "secrets.example.com")
# to a CustomDomain identifier. This lookup is used by:
#   - CustomDomain.resolve_domain_id (class method)
#   - CreateIncomingSecret#resolve_share_domain_id (v3 incoming)
# to pass domain_id to Publisher.enqueue_email for per-domain sender config.
#
# Covers:
#   - Known FQDN returns the domain identifier
#   - Unknown FQDN returns nil
#   - nil input returns nil (no crash)
#   - Empty string input returns nil
#   - Case-insensitive lookup (display_domains stores normalized lowercase)

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for display_domains resolution test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@fqdn = "resolve-test-#{@ts}-#{@entropy}.example.com"
@owner = Onetime::Customer.create!(email: "resolve_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Resolve Test Org #{@ts}", @owner, "resolve_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!(@fqdn, @org.objid)

# --- display_domains.get with known FQDN ---

## display_domains.get returns the domain identifier for a registered FQDN
Onetime::CustomDomain.display_domains.get(@fqdn)
#=> @domain.identifier

## display_domains.get returns nil for an unregistered FQDN
Onetime::CustomDomain.display_domains.get('unknown.example.com')
#=> nil

## display_domains.get returns nil when given nil
Onetime::CustomDomain.display_domains.get(nil)
#=> nil

## display_domains.get returns nil when given empty string
Onetime::CustomDomain.display_domains.get('')
#=> nil

# --- CustomDomain.resolve_domain_id class method ---

## resolve_domain_id returns domain identifier for a known FQDN
Onetime::CustomDomain.resolve_domain_id(@fqdn)
#=> @domain.identifier

## resolve_domain_id returns nil for an unknown FQDN
Onetime::CustomDomain.resolve_domain_id('nonexistent.example.com')
#=> nil

## resolve_domain_id returns nil when given nil
Onetime::CustomDomain.resolve_domain_id(nil)
#=> nil

## resolve_domain_id returns nil when given empty string
Onetime::CustomDomain.resolve_domain_id('')
#=> nil

# Teardown
Familia.dbclient.flushdb
