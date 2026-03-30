# try/integration/api/domains/list_domains_mail_fields_try.rb
#
# frozen_string_literal: true

#
# Integration tests for mail status fields in domain list API response.
#
# Verifies that mail_configured and mail_enabled fields are included in
# the CustomDomain safe_dump output, enabling UI badges for mail status.
#
# Test scenarios:
# 1. Domain without MailerConfig: mail_configured=false, mail_enabled=false
# 2. Domain with MailerConfig disabled: mail_configured=true, mail_enabled=false
# 3. Domain with MailerConfig enabled: mail_configured=true, mail_enabled=true

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Create test instance with Rack::Test::Methods
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Delegate Rack::Test methods to @test
def post(*args); @test.post(*args); end
def get(*args); @test.get(*args); end
def put(*args); @test.put(*args); end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

# Setup test data with unique identifiers
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Create test user and organization
@user = Onetime::Customer.create!(email: "mail_fields_user_#{@ts}_#{@entropy}@test.com")
@user_session = {
  'authenticated' => true,
  'external_id' => @user.extid,
  'email' => @user.email
}

@org = Onetime::Organization.create!("Mail Fields Test Org #{@ts}", @user, "mail_org_#{@ts}@test.com")

# Create three test domains
@domain_no_mail = Onetime::CustomDomain.create!("no-mail-#{@ts}.example.com", @org.objid)
@domain_mail_disabled = Onetime::CustomDomain.create!("mail-disabled-#{@ts}.example.com", @org.objid)
@domain_mail_enabled = Onetime::CustomDomain.create!("mail-enabled-#{@ts}.example.com", @org.objid)

## Setup verification - Organization has 3 domains
@org.domain_count
#=> 3

## TEST 1: Create MailerConfig for disabled domain (disabled by default)
@mailer_config_disabled = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_mail_disabled.identifier,
  provider: 'smtp',
  from_address: 'noreply@mail-disabled.example.com',
  from_name: 'Test Mail Disabled'
)
[@mailer_config_disabled.enabled?, @mailer_config_disabled.domain_id]
#=> [false, @domain_mail_disabled.identifier]

## TEST 2: Create MailerConfig for enabled domain
@mailer_config_enabled = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_mail_enabled.identifier,
  provider: 'sendgrid',
  from_address: 'noreply@mail-enabled.example.com',
  from_name: 'Test Mail Enabled',
  enabled: true
)
[@mailer_config_enabled.enabled?, @mailer_config_enabled.domain_id]
#=> [true, @domain_mail_enabled.identifier]

## TEST 3: Verify MailerConfig existence checks work
[
  Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_no_mail.identifier),
  Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_mail_disabled.identifier),
  Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_mail_enabled.identifier)
]
#=> [false, true, true]

## TEST 4: Domain list API response includes mail fields
get '/api/domains',
  { 'org_id' => @org.extid },
  {
    'rack.session' => @user_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
last_response.status
#=> 200

## TEST 5: Parse response and find our test domains
@resp = JSON.parse(last_response.body)
@domains_by_name = @resp['records'].each_with_object({}) do |d, h|
  h[d['display_domain']] = d
end
@domains_by_name.keys.sort
#=> ["mail-disabled-#{@ts}.example.com", "mail-enabled-#{@ts}.example.com", "no-mail-#{@ts}.example.com"].sort

## TEST 6: Domain without MailerConfig has mail_configured == false
@no_mail_record = @domains_by_name["no-mail-#{@ts}.example.com"]
@no_mail_record['mail_configured']
#=> false

## TEST 7: Domain without MailerConfig has mail_enabled == false
@no_mail_record['mail_enabled']
#=> false

## TEST 8: Domain with disabled MailerConfig has mail_configured == true
@disabled_mail_record = @domains_by_name["mail-disabled-#{@ts}.example.com"]
@disabled_mail_record['mail_configured']
#=> true

## TEST 9: Domain with disabled MailerConfig has mail_enabled == false
@disabled_mail_record['mail_enabled']
#=> false

## TEST 10: Domain with enabled MailerConfig has mail_configured == true
@enabled_mail_record = @domains_by_name["mail-enabled-#{@ts}.example.com"]
@enabled_mail_record['mail_configured']
#=> true

## TEST 11: Domain with enabled MailerConfig has mail_enabled == true
@enabled_mail_record['mail_enabled']
#=> true

## TEST 12: mail_configured is a boolean type (not string)
[
  @no_mail_record['mail_configured'].class,
  @disabled_mail_record['mail_configured'].class,
  @enabled_mail_record['mail_configured'].class
].all? { |klass| [TrueClass, FalseClass].include?(klass) }
#=> true

## TEST 13: mail_enabled is a boolean type (not string)
[
  @no_mail_record['mail_enabled'].class,
  @disabled_mail_record['mail_enabled'].class,
  @enabled_mail_record['mail_enabled'].class
].all? { |klass| [TrueClass, FalseClass].include?(klass) }
#=> true

## TEST 14: Individual domain fetch also includes mail fields
get "/api/domains/#{@domain_mail_enabled.extid}",
  {},
  {
    'rack.session' => @user_session.merge('organization_extid' => @org.extid),
    'HTTP_ACCEPT' => 'application/json'
  }
@single_resp = JSON.parse(last_response.body)
[@single_resp['record']['mail_configured'], @single_resp['record']['mail_enabled']]
#=> [true, true]

# Teardown - Clean up all test data
@mailer_config_disabled.destroy! if @mailer_config_disabled
@mailer_config_enabled.destroy! if @mailer_config_enabled
@domain_no_mail.destroy!
@domain_mail_disabled.destroy!
@domain_mail_enabled.destroy!
@org.destroy!
@user.destroy!
