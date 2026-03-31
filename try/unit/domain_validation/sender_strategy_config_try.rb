# try/unit/domain_validation/sender_strategy_config_try.rb
#
# frozen_string_literal: true

# Tests for sender strategy configuration externalization (#2835)
#
# Validates:
# 1. Strategies accept config options in constructors
# 2. Factory merges ProviderConfig defaults with explicit options
# 3. Strategies use instance variables from config, not class constants
# 4. Backward compatibility: no config = same behavior as before

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/strategy'

SenderStrategy = Onetime::DomainValidation::SenderStrategies::SenderStrategy
SesValidation = Onetime::DomainValidation::SenderStrategies::SesValidation
SendgridValidation = Onetime::DomainValidation::SenderStrategies::SendgridValidation
LettermintValidation = Onetime::DomainValidation::SenderStrategies::LettermintValidation

# Setup: create test fixtures
@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "ssc_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("SSC Test Org #{@timestamp}", @owner, "ssc_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("ssc-test-#{@timestamp}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Test Sender',
  from_address: "noreply@ssc-test-#{@timestamp}.example.com",
)

# --- SES Strategy accepts_options ---

## SES accepts_options includes region
SesValidation.accepted_options.include?(:region)
#=> true

## SES accepts_options includes dkim_selector_count
SesValidation.accepted_options.include?(:dkim_selector_count)
#=> true

## SES accepts_options includes spf_include
SesValidation.accepted_options.include?(:spf_include)
#=> true

# --- SendGrid Strategy accepts_options ---

## SendGrid accepts_options includes subdomain
SendgridValidation.accepted_options.include?(:subdomain)
#=> true

## SendGrid accepts_options includes dkim_selectors
SendgridValidation.accepted_options.include?(:dkim_selectors)
#=> true

## SendGrid accepts_options includes spf_include
SendgridValidation.accepted_options.include?(:spf_include)
#=> true

# --- Lettermint Strategy accepts_options ---

## Lettermint accepts_options includes dkim_selectors
LettermintValidation.accepted_options.include?(:dkim_selectors)
#=> true

## Lettermint accepts_options includes spf_include
LettermintValidation.accepted_options.include?(:spf_include)
#=> true

# --- Factory uses ProviderConfig defaults ---

## Factory creates SES with default region
strategy = SenderStrategy.for_provider('ses')
records = strategy.required_dns_records(@config)
mx_record = records.find { |r| r[:type] == 'MX' }
mx_record[:value].include?('us-east-1')
#=> true

## Factory creates SES with explicit region override
strategy = SenderStrategy.for_provider('ses', region: 'eu-west-1')
records = strategy.required_dns_records(@config)
mx_record = records.find { |r| r[:type] == 'MX' }
mx_record[:value].include?('eu-west-1')
#=> true

## Factory creates SendGrid with default subdomain
strategy = SenderStrategy.for_provider('sendgrid')
records = strategy.required_dns_records(@config)
link_record = records.find { |r| r[:purpose].include?('link branding') }
link_record[:host].start_with?('em.')
#=> true

## Factory creates SendGrid with explicit subdomain override
strategy = SenderStrategy.for_provider('sendgrid', subdomain: 'mail')
records = strategy.required_dns_records(@config)
link_record = records.find { |r| r[:purpose].include?('link branding') }
link_record[:host].start_with?('mail.')
#=> true

# --- SES uses instance variables for DNS record generation ---

## SES with custom dkim_selector_count generates correct number of records
strategy = SenderStrategy.for_provider('ses', dkim_selector_count: 5)
records = strategy.required_dns_records(@config)
dkim_records = records.select { |r| r[:purpose].include?('DKIM signature') }
dkim_records.size
#=> 5

## SES with custom spf_include uses it in DKIM CNAME values
strategy = SenderStrategy.for_provider('ses', spf_include: 'custom-ses.example.com')
records = strategy.required_dns_records(@config)
dkim_record = records.find { |r| r[:purpose].include?('DKIM signature 1') }
dkim_record[:value].include?('custom-ses.example.com')
#=> true

## SES with custom spf_include uses it in SPF TXT value
strategy = SenderStrategy.for_provider('ses', spf_include: 'custom-ses.example.com')
records = strategy.required_dns_records(@config)
spf_record = records.find { |r| r[:purpose] == 'SPF authentication' }
spf_record[:value].include?('custom-ses.example.com')
#=> true

# --- SendGrid uses instance variables for DNS record generation ---

## SendGrid with custom dkim_selectors generates correct selectors
strategy = SenderStrategy.for_provider('sendgrid', dkim_selectors: ['dk1', 'dk2', 'dk3'])
records = strategy.required_dns_records(@config)
dkim_records = records.select { |r| r[:purpose].include?('DKIM signature') }
dkim_records.size
#=> 3

## SendGrid with custom dkim_selectors uses them in host names
strategy = SenderStrategy.for_provider('sendgrid', dkim_selectors: ['dk1', 'dk2'])
records = strategy.required_dns_records(@config)
dkim_record = records.find { |r| r[:purpose].include?('DKIM signature 1') }
dkim_record[:host].start_with?('dk1._domainkey.')
#=> true

## SendGrid with custom spf_include uses it in CNAME values
# Verifies custom SPF include domain appears in link branding record
strategy = SenderStrategy.for_provider('sendgrid', spf_include: 'custom-sg.example.com')
records = strategy.required_dns_records(@config)
link_record = records.find { |r| r[:purpose].include?('link branding') }
link_record[:value].end_with?('custom-sg.example.com')
#=> true

# --- Lettermint uses instance variables for DNS record generation ---

## Lettermint with custom dkim_selectors generates correct selectors
strategy = SenderStrategy.for_provider('lettermint', dkim_selectors: ['k1', 'k2', 'k3'])
records = strategy.required_dns_records(@config)
dkim_records = records.select { |r| r[:purpose].include?('DKIM signature') }
dkim_records.size
#=> 3

## Lettermint with custom dkim_selectors uses them in host names
strategy = SenderStrategy.for_provider('lettermint', dkim_selectors: ['k1', 'k2'])
records = strategy.required_dns_records(@config)
dkim_record = records.find { |r| r[:purpose].include?('DKIM signature 1') }
dkim_record[:host].start_with?('k1._domainkey.')
#=> true

## Lettermint with custom spf_include uses it in CNAME values
strategy = SenderStrategy.for_provider('lettermint', spf_include: 'custom-lm.example.com')
records = strategy.required_dns_records(@config)
dkim_record = records.find { |r| r[:purpose].include?('DKIM signature 1') }
dkim_record[:value].include?('custom-lm.example.com')
#=> true

# --- Backward compatibility: default values match legacy constants ---

## SES default region matches legacy DEFAULT_REGION constant
SesValidation::DEFAULT_REGION
#=> 'us-east-1'

## SES default dkim count matches legacy DKIM_SELECTOR_COUNT constant
SesValidation::DKIM_SELECTOR_COUNT
#=> 3

## SES default spf_include matches legacy SPF_INCLUDE constant
SesValidation::SPF_INCLUDE
#=> 'amazonses.com'

## SendGrid default subdomain matches legacy DEFAULT_SUBDOMAIN constant
SendgridValidation::DEFAULT_SUBDOMAIN
#=> 'em'

## SendGrid default selectors match legacy DKIM_SELECTORS constant
SendgridValidation::DKIM_SELECTORS
#=> ['s1', 's2']

## Lettermint default selectors match legacy DKIM_SELECTORS constant
LettermintValidation::DKIM_SELECTORS
#=> ['lm1', 'lm2']

# --- Strategy constructor direct instantiation ---

## SES strategy can be instantiated directly with options
strategy = SesValidation.new(region: 'ap-southeast-1', dkim_selector_count: 2)
records = strategy.required_dns_records(@config)
mx_record = records.find { |r| r[:type] == 'MX' }
mx_record[:value].include?('ap-southeast-1')
#=> true

## SendGrid strategy can be instantiated directly with options
strategy = SendgridValidation.new(subdomain: 'tracking', dkim_selectors: ['x1'])
records = strategy.required_dns_records(@config)
link_record = records.find { |r| r[:purpose].include?('link branding') }
link_record[:host].start_with?('tracking.')
#=> true

## Lettermint strategy can be instantiated directly with options
strategy = LettermintValidation.new(dkim_selectors: ['custom1'], spf_include: 'custom.example.com')
records = strategy.required_dns_records(@config)
records.size
#=> 2

# Teardown
Familia.dbclient.flushdb
