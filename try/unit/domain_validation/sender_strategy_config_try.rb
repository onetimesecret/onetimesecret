# try/unit/domain_validation/sender_strategy_config_try.rb
#
# frozen_string_literal: true

# Tests for sender strategy provisioned-records behavior
#
# Validates:
# 1. Strategies read dns_records from mailer_config (not hardcoded)
# 2. Strategies return empty array when no provisioned records exist
# 3. Record purpose classification per provider
# 4. String-keyed hashes mapped to symbol-keyed output
# 5. Factory creates strategies without options (no configurable knobs)

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/strategy'

SenderStrategy = Onetime::DomainValidation::SenderStrategies::SenderStrategy
SesValidation = Onetime::DomainValidation::SenderStrategies::SesValidation
SendgridValidation = Onetime::DomainValidation::SenderStrategies::SendgridValidation
LettermintValidation = Onetime::DomainValidation::SenderStrategies::LettermintValidation

# Helper struct that mimics dns_records accessor on MailerConfig
DnsRecordsWrapper = Struct.new(:value)

# Build mock mailer configs with provisioned dns_records.
# Strategies call mailer_config.dns_records.value to get an array
# of string-keyed hashes as stored from provider APIs.
@ses_dns = DnsRecordsWrapper.new([
  {'type' => 'CNAME', 'name' => 'tok1._domainkey.config-test.example.com', 'value' => 'tok1.dkim.amazonses.com'},
  {'type' => 'CNAME', 'name' => 'tok2._domainkey.config-test.example.com', 'value' => 'tok2.dkim.amazonses.com'},
  {'type' => 'TXT',   'name' => 'config-test.example.com', 'value' => 'v=spf1 include:amazonses.com ~all'},
  {'type' => 'MX',    'name' => 'config-test.example.com', 'value' => '10 inbound-smtp.us-east-1.amazonaws.com'},
])

@sg_dns = DnsRecordsWrapper.new([
  {'type' => 'CNAME', 'name' => 's1._domainkey.config-test.example.com', 'value' => 's1.domainkey.u999.wl.sendgrid.net'},
  {'type' => 'CNAME', 'name' => 's2._domainkey.config-test.example.com', 'value' => 's2.domainkey.u999.wl.sendgrid.net'},
  {'type' => 'CNAME', 'name' => 'em.config-test.example.com', 'value' => 'u999.wl.sendgrid.net'},
  {'type' => 'TXT',   'name' => 'config-test.example.com', 'value' => 'v=spf1 include:sendgrid.net ~all'},
])

@lm_dns = DnsRecordsWrapper.new([
  {'type' => 'TXT',   'name' => 'lettermint._domainkey.config-test.example.com', 'value' => 'v=DKIM1;k=rsa;p=TESTKEY'},
  {'type' => 'CNAME', 'name' => 'lm-bounces.config-test.example.com', 'value' => 'bounces.lmta.net'},
  {'type' => 'TXT',   'name' => '_dmarc.config-test.example.com', 'value' => 'v=DMARC1;p=none'},
])

MockConfig = Struct.new(:domain_id, :provider, :from_address, :dns_records)

@ses_config = MockConfig.new('cd:ses-test', 'ses', 'noreply@config-test.example.com', @ses_dns)
@sg_config  = MockConfig.new('cd:sg-test', 'sendgrid', 'noreply@config-test.example.com', @sg_dns)
@lm_config  = MockConfig.new('cd:lm-test', 'lettermint', 'noreply@config-test.example.com', @lm_dns)

@empty_config = MockConfig.new('cd:empty', 'ses', 'noreply@config-test.example.com', DnsRecordsWrapper.new([]))
@nil_config   = MockConfig.new('cd:nil', 'ses', 'noreply@config-test.example.com', nil)

# --- Strategies have no configurable options ---

## SES accepted_options is empty
SesValidation.accepted_options
#=> []

## SendGrid accepted_options is empty
SendgridValidation.accepted_options
#=> []

## Lettermint accepted_options is empty
LettermintValidation.accepted_options
#=> []

# --- Factory creates strategies without options ---

## Factory creates SES strategy
SenderStrategy.for_provider('ses').class
#=> Onetime::DomainValidation::SenderStrategies::SesValidation

## Factory creates SendGrid strategy
SenderStrategy.for_provider('sendgrid').class
#=> Onetime::DomainValidation::SenderStrategies::SendgridValidation

## Factory creates Lettermint strategy
SenderStrategy.for_provider('lettermint').class
#=> Onetime::DomainValidation::SenderStrategies::LettermintValidation

# --- SES reads provisioned records ---

## SES returns records from mailer_config.dns_records
strategy = SenderStrategy.for_provider('ses')
records = strategy.required_dns_records(@ses_config)
records.size
#=> 4

## SES maps string-keyed hash to symbol-keyed output
record = SenderStrategy.for_provider('ses').required_dns_records(@ses_config).first
record.keys.all? { |k| k.is_a?(Symbol) }
#=> true

## SES DKIM records have purpose 'DKIM'
strategy = SenderStrategy.for_provider('ses')
records = strategy.required_dns_records(@ses_config)
dkim = records.select { |r| r[:host].include?('_domainkey') }
dkim.all? { |r| r[:purpose] == 'DKIM' }
#=> true

## SES SPF record has purpose 'SPF'
strategy = SenderStrategy.for_provider('ses')
records = strategy.required_dns_records(@ses_config)
spf = records.find { |r| r[:type] == 'TXT' && r[:value].include?('v=spf1') }
spf[:purpose]
#=> 'SPF'

## SES MX record has purpose for bounce handling
strategy = SenderStrategy.for_provider('ses')
records = strategy.required_dns_records(@ses_config)
mx = records.find { |r| r[:type] == 'MX' }
mx[:purpose]
#=> 'Inbound mail (bounce handling)'

# --- SendGrid reads provisioned records ---

## SendGrid returns records from mailer_config.dns_records
strategy = SenderStrategy.for_provider('sendgrid')
records = strategy.required_dns_records(@sg_config)
records.size
#=> 4

## SendGrid DKIM records classified correctly
strategy = SenderStrategy.for_provider('sendgrid')
records = strategy.required_dns_records(@sg_config)
dkim = records.select { |r| r[:host].include?('_domainkey') }
dkim.all? { |r| r[:purpose] == 'DKIM' }
#=> true

## SendGrid link branding CNAME classified correctly
strategy = SenderStrategy.for_provider('sendgrid')
records = strategy.required_dns_records(@sg_config)
link = records.find { |r| r[:host] == 'em.config-test.example.com' }
link[:purpose]
#=> 'Link branding / return-path'

## SendGrid SPF record classified correctly
strategy = SenderStrategy.for_provider('sendgrid')
records = strategy.required_dns_records(@sg_config)
spf = records.find { |r| r[:type] == 'TXT' && r[:value].include?('v=spf1') }
spf[:purpose]
#=> 'SPF'

# --- Lettermint reads provisioned records ---

## Lettermint returns records from mailer_config.dns_records
strategy = SenderStrategy.for_provider('lettermint')
records = strategy.required_dns_records(@lm_config)
records.size
#=> 3

## Lettermint DKIM record classified correctly
strategy = SenderStrategy.for_provider('lettermint')
records = strategy.required_dns_records(@lm_config)
dkim = records.find { |r| r[:host].include?('_domainkey') }
dkim[:purpose]
#=> 'DKIM'

## Lettermint bounce record classified as SPF/Return-Path
strategy = SenderStrategy.for_provider('lettermint')
records = strategy.required_dns_records(@lm_config)
bounce = records.find { |r| r[:host].include?('lm-bounces') }
bounce[:purpose]
#=> 'SPF/Return-Path'

## Lettermint DMARC record classified correctly
strategy = SenderStrategy.for_provider('lettermint')
records = strategy.required_dns_records(@lm_config)
dmarc = records.find { |r| r[:host].include?('_dmarc') }
dmarc[:purpose]
#=> 'DMARC'

# --- Empty / nil provisioned records ---

## Empty provisioned records returns empty array for SES
SenderStrategy.for_provider('ses').required_dns_records(@empty_config)
#=> []

## Nil dns_records returns empty array for SES
SenderStrategy.for_provider('ses').required_dns_records(@nil_config)
#=> []

## Empty provisioned records returns empty array for SendGrid
SenderStrategy.for_provider('sendgrid').required_dns_records(@empty_config)
#=> []

## Empty provisioned records returns empty array for Lettermint
SenderStrategy.for_provider('lettermint').required_dns_records(@empty_config)
#=> []

# --- Record structure validation ---

## All records have required keys (type, host, value, purpose)
all_records = []
all_records += SenderStrategy.for_provider('ses').required_dns_records(@ses_config)
all_records += SenderStrategy.for_provider('sendgrid').required_dns_records(@sg_config)
all_records += SenderStrategy.for_provider('lettermint').required_dns_records(@lm_config)
required_keys = [:type, :host, :value, :purpose]
all_records.all? { |r| required_keys.all? { |k| r.key?(k) } }
#=> true

## All record values are strings (mapped from string-keyed hashes)
all_records = []
all_records += SenderStrategy.for_provider('ses').required_dns_records(@ses_config)
all_records += SenderStrategy.for_provider('sendgrid').required_dns_records(@sg_config)
all_records += SenderStrategy.for_provider('lettermint').required_dns_records(@lm_config)
all_records.all? { |r| r[:type].is_a?(String) && r[:host].is_a?(String) && r[:value].is_a?(String) }
#=> true

## Record types are uppercased
all_records = SenderStrategy.for_provider('ses').required_dns_records(@ses_config)
all_records.all? { |r| r[:type] == r[:type].upcase }
#=> true

# --- Different provisioned records produce different output ---

## Two configs with different provisioned records produce different results
alt_dns = DnsRecordsWrapper.new([
  {'type' => 'CNAME', 'name' => 'alt._domainkey.other.com', 'value' => 'alt.dkim.amazonses.com'},
])
alt_config = MockConfig.new('cd:alt', 'ses', 'noreply@other.com', alt_dns)
strategy = SenderStrategy.for_provider('ses')
strategy.required_dns_records(@ses_config).size != strategy.required_dns_records(alt_config).size
#=> true
