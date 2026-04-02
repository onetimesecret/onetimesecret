# try/unit/models/custom_domain_navigation_try.rb
#
# frozen_string_literal: true

# Unit tests for CustomDomain forward navigation methods:
#   - sso_config / sso_config?
#   - mailer_config / mailer_config?
#
# These methods provide 1:1 navigation from CustomDomain to its
# associated SsoConfig and MailerConfig records (or nil when absent).
#
# Issue: #2801 - Custom domain configs

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for CustomDomain navigation test run"

# Familia encryption config required by SsoConfig encrypted fields
@key_v1 = 'test_encryption_key_32bytes_ok!!'
@key_v2 = 'another_test_key_for_testing_!!'

Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(@key_v1),
    v2: Base64.strict_encode64(@key_v2),
  }
  config.current_key_version = :v1
  config.encryption_personalization = 'CustomDomainNavTest'
end

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

@owner = Onetime::Customer.create!(email: "nav_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Nav Test Org #{@ts}", @owner, "nav_#{@ts}@test.com")

# Domain WITH both configs
@domain_with = Onetime::CustomDomain.create!("nav-with-#{@ts}-#{@entropy}.example.com", @org.objid)

@sso = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain_with.identifier,
  provider_type: 'oidc',
  client_id: "client-#{@entropy}",
  client_secret: "secret-#{@entropy}",
  issuer: 'https://auth.example.com',
  display_name: 'Nav Test SSO',
  enabled: true,
)

@mailer = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_with.identifier,
  provider: 'ses',
  from_name: 'Nav Test Sender',
  from_address: "noreply@nav-#{@entropy}.example.com",
  api_key: "key-#{@entropy}",
)

# Domain WITHOUT any configs
@domain_without = Onetime::CustomDomain.create!("nav-without-#{@ts}-#{@entropy}.example.com", @org.objid)

# --- sso_config navigation (config present) ---

## sso_config returns a SsoConfig instance when one exists
@domain_with.sso_config.class
#=> Onetime::CustomDomain::SsoConfig

## sso_config has the correct domain_id
@domain_with.sso_config.domain_id
#=> @domain_with.identifier

## sso_config? returns true when config exists
@domain_with.sso_config?
#=> true

# --- mailer_config navigation (config present) ---

## mailer_config returns a MailerConfig instance when one exists
@domain_with.mailer_config.class
#=> Onetime::CustomDomain::MailerConfig

## mailer_config has the correct domain_id
@domain_with.mailer_config.domain_id
#=> @domain_with.identifier

## mailer_config? returns true when config exists
@domain_with.mailer_config?
#=> true

# --- Navigation for domain without configs ---

## Domain without configs was created successfully
@domain_without.class
#=> Onetime::CustomDomain

## sso_config returns nil for domain without config
@domain_without.sso_config.nil?
#=> true

## sso_config? returns false for domain without config
@domain_without.sso_config?
#=> false

## mailer_config returns nil for domain without config
@domain_without.mailer_config.nil?
#=> true

## mailer_config? returns false for domain without config
@domain_without.mailer_config?
#=> false

# Teardown
Familia.dbclient.flushdb
