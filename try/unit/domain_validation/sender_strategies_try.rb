# try/unit/domain_validation/sender_strategies_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::DomainValidation::SenderStrategies
#
# Validates:
# 1. Factory routing for each provider type (ses, sendgrid, lettermint)
# 2. Factory rejection of unknown providers
# 3. DNS records read from provisioned mailer_config.dns_records
# 4. Record hash structure (required keys)
# 5. Strategy name strings
# 6. SPF record matching logic (record_matches?)
# 7. Empty provisioned records returns empty array

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/strategy'

# Helper to build a dns_records wrapper for mock mailer configs.
# Strategies read mailer_config.dns_records.value which returns an
# array of string-keyed hashes (as stored from provider APIs).
DnsWrapper = Struct.new(:value)

# Provisioned records for each provider, mimicking what the provider
# APIs return and what gets stored in mailer_config.dns_records.
@ses_provisioned = [
  {'type' => 'CNAME', 'name' => 'abc123._domainkey.example.com', 'value' => 'abc123.dkim.amazonses.com'},
  {'type' => 'CNAME', 'name' => 'def456._domainkey.example.com', 'value' => 'def456.dkim.amazonses.com'},
  {'type' => 'CNAME', 'name' => 'ghi789._domainkey.example.com', 'value' => 'ghi789.dkim.amazonses.com'},
  {'type' => 'TXT',   'name' => 'example.com', 'value' => 'v=spf1 include:amazonses.com ~all'},
  {'type' => 'MX',    'name' => 'example.com', 'value' => '10 inbound-smtp.us-east-1.amazonaws.com'},
]

@sg_provisioned = [
  {'type' => 'CNAME', 'name' => 's1._domainkey.example.com', 'value' => 's1.domainkey.u12345.wl.sendgrid.net'},
  {'type' => 'CNAME', 'name' => 's2._domainkey.example.com', 'value' => 's2.domainkey.u12345.wl.sendgrid.net'},
  {'type' => 'CNAME', 'name' => 'em.example.com', 'value' => 'u12345.wl.sendgrid.net'},
  {'type' => 'TXT',   'name' => 'example.com', 'value' => 'v=spf1 include:sendgrid.net ~all'},
]

@lm_provisioned = [
  {'type' => 'TXT',   'name' => 'lettermint._domainkey.example.com', 'value' => 'v=DKIM1;k=rsa;p=TESTKEY'},
  {'type' => 'CNAME', 'name' => 'lm-bounces.example.com', 'value' => 'bounces.lmta.net'},
  {'type' => 'TXT',   'name' => '_dmarc.example.com', 'value' => 'v=DMARC1;p=none'},
]

# Build mock mailer configs with dns_records for each provider.
# Strategies resolve the sender domain from mailer_config.from_address.
@mock_custom_domain = Struct.new(:display_domain, :identifier).new(
  'secrets.example.com', 'cd:test123'
)

@mock_ses_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address, :dns_records).new(
  @mock_custom_domain, 'cd:test123', 'ses', 'sender@example.com',
  DnsWrapper.new(@ses_provisioned)
)

@mock_sg_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address, :dns_records).new(
  @mock_custom_domain, 'cd:test123', 'sendgrid', 'sender@example.com',
  DnsWrapper.new(@sg_provisioned)
)

@mock_lm_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address, :dns_records).new(
  @mock_custom_domain, 'cd:test123', 'lettermint', 'sender@example.com',
  DnsWrapper.new(@lm_provisioned)
)

@mock_empty_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address, :dns_records).new(
  @mock_custom_domain, 'cd:test123', 'ses', 'sender@example.com',
  DnsWrapper.new([])
)

@mock_nil_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address, :dns_records).new(
  @mock_custom_domain, 'cd:test123', 'ses', 'sender@example.com',
  nil
)

@factory = Onetime::DomainValidation::SenderStrategies::SenderStrategy

# Pre-generate all records in setup so they are available to all test cases
@ses = @factory.for_provider('ses')
@ses_records = @ses.required_dns_records(@mock_ses_config)

@sg = @factory.for_provider('sendgrid')
@sg_records = @sg.required_dns_records(@mock_sg_config)

@lm = @factory.for_provider('lettermint')
@lm_records = @lm.required_dns_records(@mock_lm_config)

@all_records = @ses_records + @sg_records + @lm_records

# For SPF matching tests
@base = @factory.for_provider('ses')

# --- Factory routing ---

## Factory returns SesValidation for 'ses'
@factory.for_provider('ses').class
#=> Onetime::DomainValidation::SenderStrategies::SesValidation

## Factory returns SendgridValidation for 'sendgrid'
@factory.for_provider('sendgrid').class
#=> Onetime::DomainValidation::SenderStrategies::SendgridValidation

## Factory returns LettermintValidation for 'lettermint'
@factory.for_provider('lettermint').class
#=> Onetime::DomainValidation::SenderStrategies::LettermintValidation

## Factory normalizes provider string (uppercase, whitespace)
@factory.for_provider('  SES  ').class
#=> Onetime::DomainValidation::SenderStrategies::SesValidation

## Factory normalizes symbol input
@factory.for_provider(:sendgrid).class
#=> Onetime::DomainValidation::SenderStrategies::SendgridValidation

## Factory raises ArgumentError for unknown provider
begin
  @factory.for_provider('mailchimp')
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?("Unknown mail provider: 'mailchimp'")
end
#=> true

## Factory raises ArgumentError for empty string
begin
  @factory.for_provider('')
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?('Unknown mail provider')
end
#=> true

# --- Strategy names ---

## SES strategy name is 'ses'
@factory.for_provider('ses').strategy_name
#=> 'ses'

## SendGrid strategy name is 'sendgrid'
@factory.for_provider('sendgrid').strategy_name
#=> 'sendgrid'

## Lettermint strategy name is 'lettermint'
@factory.for_provider('lettermint').strategy_name
#=> 'lettermint'

# --- SES record generation from provisioned data ---

## SES reads 5 records from provisioned dns_records
@ses_records.size
#=> 5

## SES maps CNAME records from provisioned data
@ses_records.count { |r| r[:type] == 'CNAME' }
#=> 3

## SES maps TXT records from provisioned data
@ses_records.count { |r| r[:type] == 'TXT' }
#=> 1

## SES maps MX records from provisioned data
@ses_records.count { |r| r[:type] == 'MX' }
#=> 1

## SES CNAME hosts include _domainkey subdomain
@ses_records.select { |r| r[:type] == 'CNAME' }.all? { |r| r[:host].include?('._domainkey.') }
#=> true

## SES DKIM purpose is classified correctly
@ses_records.select { |r| r[:type] == 'CNAME' }.all? { |r| r[:purpose] == 'DKIM' }
#=> true

## SES SPF record classified correctly
@ses_spf = @ses_records.find { |r| r[:purpose] == 'SPF' }
@ses_spf[:type]
#=> 'TXT'

## SES MX record classified as bounce handling
@ses_mx = @ses_records.find { |r| r[:type] == 'MX' }
@ses_mx[:purpose]
#=> 'Inbound mail (bounce handling)'

## SES records all use the sender domain from from_address
# DNS hostname suffix assertion with label boundary (exact domain or subdomain only)
@ses_records.all? { |r| r[:host] == 'example.com' || r[:host].end_with?('.example.com') }
#=> true

# --- SendGrid record generation from provisioned data ---

## SendGrid reads 4 records from provisioned dns_records
@sg_records.size
#=> 4

## SendGrid maps CNAME records from provisioned data
@sg_records.count { |r| r[:type] == 'CNAME' }
#=> 3

## SendGrid maps TXT records from provisioned data
@sg_records.count { |r| r[:type] == 'TXT' }
#=> 1

## SendGrid DKIM CNAMEs use s1 and s2 selectors from provisioned data
@sg_dkim = @sg_records.select { |r| r[:type] == 'CNAME' && r[:host].include?('._domainkey.') }
@sg_dkim.map { |r| r[:host].split('.').first }.sort
#=> ['s1', 's2']

## SendGrid link branding record classified correctly
@sg_link = @sg_records.find { |r| r[:host] == 'em.example.com' }
@sg_link[:purpose]
#=> 'Link branding / return-path'

# --- Lettermint record generation from provisioned data ---

## Lettermint reads 3 records from provisioned dns_records
@lm_records.size
#=> 3

## Lettermint DKIM record classified correctly
@lm_dkim = @lm_records.find { |r| r[:host].include?('_domainkey') }
@lm_dkim[:purpose]
#=> 'DKIM'

## Lettermint bounce CNAME classified as SPF/Return-Path
@lm_bounce = @lm_records.find { |r| r[:host].include?('lm-bounces') }
@lm_bounce[:purpose]
#=> 'SPF/Return-Path'

## Lettermint DMARC record classified correctly
@lm_dmarc = @lm_records.find { |r| r[:host].include?('_dmarc') }
@lm_dmarc[:purpose]
#=> 'DMARC'

# --- Empty / nil provisioned records ---

## Empty provisioned records returns empty array
@ses.required_dns_records(@mock_empty_config)
#=> []

## Nil dns_records returns empty array
@ses.required_dns_records(@mock_nil_config)
#=> []

# --- Record hash structure ---

## All records from every provider have required keys
@required_keys = [:type, :host, :value, :purpose]
@all_records.all? { |r| @required_keys.all? { |k| r.key?(k) } }
#=> true

## No record has nil values for required keys
@all_records.all? { |r| [:type, :host, :value, :purpose].all? { |k| !r[k].nil? } }
#=> true

## All record types are valid DNS types
@all_records.all? { |r| %w[TXT CNAME MX].include?(r[:type]) }
#=> true

## All purpose strings are non-empty
@all_records.all? { |r| r[:purpose].to_s.length > 0 }
#=> true

# --- accepted_options returns empty (no configurable options) ---

## SES accepted_options is empty
Onetime::DomainValidation::SenderStrategies::SesValidation.accepted_options
#=> []

## SendGrid accepted_options is empty
Onetime::DomainValidation::SenderStrategies::SendgridValidation.accepted_options
#=> []

## Lettermint accepted_options is empty
Onetime::DomainValidation::SenderStrategies::LettermintValidation.accepted_options
#=> []

# --- Factory rejects unknown options ---

## Factory rejects unknown option for SES with clear error
begin
  @factory.for_provider('ses', bogus_option: 'value')
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?("Unknown option(s)") && e.message.include?("'ses'")
end
#=> true

## Factory rejects unknown option for SendGrid with clear error
begin
  @factory.for_provider('sendgrid', bogus_option: 'value')
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?("Unknown option(s)") && e.message.include?("'sendgrid'")
end
#=> true

## Factory rejects unknown option for Lettermint with clear error
begin
  @factory.for_provider('lettermint', bogus_option: 'value')
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?("Unknown option(s)") && e.message.include?("'lettermint'")
end
#=> true

## Lettermint strategy accepts empty options without error
@factory.for_provider('lettermint', {}).class
#=> Onetime::DomainValidation::SenderStrategies::LettermintValidation

# --- SPF matching logic (record_matches? via BaseStrategy) ---

## SPF match succeeds when include directive is present in actual TXT
@base.send(:record_matches?, 'TXT',
  'v=spf1 include:amazonses.com ~all',
  ['v=spf1 include:amazonses.com include:sendgrid.net ~all'])
#=> true

## SPF match fails when include directive is absent
@base.send(:record_matches?, 'TXT',
  'v=spf1 include:amazonses.com ~all',
  ['v=spf1 include:sendgrid.net ~all'])
#=> false

## SPF match fails against non-SPF TXT record
@base.send(:record_matches?, 'TXT',
  'v=spf1 include:amazonses.com ~all',
  ['some-verification-token'])
#=> false

## CNAME match is case-insensitive
@base.send(:record_matches?, 'CNAME',
  'token.dkim.amazonses.com',
  ['TOKEN.DKIM.AMAZONSES.COM'])
#=> true

## CNAME match ignores trailing dots
@base.send(:record_matches?, 'CNAME',
  'token.dkim.amazonses.com',
  ['token.dkim.amazonses.com.'])
#=> true

## MX match is case-insensitive and strips trailing dots
@base.send(:record_matches?, 'MX',
  'inbound-smtp.us-east-1.amazonaws.com',
  ['inbound-smtp.us-east-1.amazonaws.com.'])
#=> true

## Unknown record type returns false
@base.send(:record_matches?, 'AAAA', 'value', ['value'])
#=> false

# --- Edge case: resolve_domain with missing from_address ---

## resolve_domain raises ArgumentError when from_address is nil
@broken_config = Struct.new(:from_address, :domain_id).new(nil, 'cd:missing')
begin
  @base.send(:resolve_domain, @broken_config)
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?('has no valid from_address')
end
#=> true

# --- Edge case: resolve_domain with invalid from_address ---

## resolve_domain raises ArgumentError when from_address has no @ sign
@invalid_config = Struct.new(:from_address, :domain_id).new('no-at-sign', 'cd:invalid')
begin
  @base.send(:resolve_domain, @invalid_config)
  'unexpected_success'
rescue ArgumentError => e
  e.message.include?('has no valid from_address')
end
#=> true
