# try/unit/models/custom_domain_mail_fields_try.rb
#
# frozen_string_literal: true

# Tests for mail_configured and mail_enabled safe_dump fields on CustomDomain.
#
# These fields mirror the sso_configured/sso_enabled pattern: a pair of
# computed fields backed by a per-object instance variable cache. The cache
# avoids N+1 lookups when serializing domain lists.
#
# Scenarios:
#   1. Domain without MailerConfig: mail_configured=false, mail_enabled=false
#   2. Domain with disabled MailerConfig: mail_configured=true, mail_enabled=false
#   3. Domain with enabled MailerConfig: mail_configured=true, mail_enabled=true

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for mail_fields test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "mf_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("MF Test Org #{@ts}", @owner, "mf_#{@ts}@test.com")

@domain_no_mail = Onetime::CustomDomain.create!("no-mail-#{@ts}.example.com", @org.objid)
@domain_mail_off = Onetime::CustomDomain.create!("mail-off-#{@ts}.example.com", @org.objid)
@domain_mail_on = Onetime::CustomDomain.create!("mail-on-#{@ts}.example.com", @org.objid)

## Setup: three domains created
@org.domain_count
#=> 3

## Create disabled MailerConfig for mail-off domain
@mc_off = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_mail_off.identifier,
  provider: 'ses',
  from_address: 'off@example.com'
)
@mc_off.enabled?
#=> false

## Create enabled MailerConfig for mail-on domain
@mc_on = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_mail_on.identifier,
  provider: 'sendgrid',
  from_address: 'on@example.com',
  enabled: true
)
@mc_on.enabled?
#=> true

# --- safe_dump field tests ---

## Domain without mail config: safe_dump includes mail_configured=false
@dump_no_mail = @domain_no_mail.safe_dump
@dump_no_mail[:mail_configured]
#=> false

## Domain without mail config: safe_dump includes mail_enabled=false
@dump_no_mail[:mail_enabled]
#=> false

## Domain with disabled mail config: safe_dump includes mail_configured=true
@dump_mail_off = @domain_mail_off.safe_dump
@dump_mail_off[:mail_configured]
#=> true

## Domain with disabled mail config: safe_dump includes mail_enabled=false
@dump_mail_off[:mail_enabled]
#=> false

## Domain with enabled mail config: safe_dump includes mail_configured=true
@dump_mail_on = @domain_mail_on.safe_dump
@dump_mail_on[:mail_configured]
#=> true

## Domain with enabled mail config: safe_dump includes mail_enabled=true
@dump_mail_on[:mail_enabled]
#=> true

## safe_dump mail fields are booleans not strings
[
  @dump_no_mail[:mail_configured].class,
  @dump_no_mail[:mail_enabled].class,
  @dump_mail_on[:mail_configured].class,
  @dump_mail_on[:mail_enabled].class
].all? { |klass| [TrueClass, FalseClass].include?(klass) }
#=> true

# --- SSO fields are still present ---

## safe_dump still includes sso_configured field
@dump_no_mail.key?(:sso_configured)
#=> true

## safe_dump still includes sso_enabled field
@dump_no_mail.key?(:sso_enabled)
#=> true

# --- Cache isolation: fresh instances get fresh lookups ---

## Enabling mail config mid-flight is reflected in a new safe_dump
@mc_off.enabled = 'true'
@mc_off.save
@fresh_domain = Onetime::CustomDomain.find_by_identifier(@domain_mail_off.identifier)
@fresh_dump = @fresh_domain.safe_dump
@fresh_dump[:mail_enabled]
#=> true

## Disabling config is reflected in a new instance safe_dump
@mc_off.enabled = 'false'
@mc_off.save
@fresh2 = Onetime::CustomDomain.find_by_identifier(@domain_mail_off.identifier)
@fresh2.safe_dump[:mail_enabled]
#=> false

# Teardown
Familia.dbclient.flushdb
