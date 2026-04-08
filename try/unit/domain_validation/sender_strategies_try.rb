# try/unit/domain_validation/sender_strategies_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::DomainValidation::SenderStrategies
#
# Validates:
# 1. Factory routing for each provider type (ses, sendgrid, lettermint)
# 2. Factory rejection of unknown providers
# 3. DNS record counts per provider
# 4. Record hash structure (required keys)
# 5. Strategy name strings
# 6. DNS record type distributions match provider specs
# 7. SPF record matching logic (record_matches?)

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/strategy'

# Stub mailer_config and custom_domain for record generation.
# Strategies resolve the sender domain from mailer_config.from_address.
@mock_custom_domain = Struct.new(:display_domain, :identifier).new(
  'secrets.example.com', 'cd:test123'
)
@mock_mailer_config = Struct.new(:custom_domain, :domain_id, :provider, :from_address).new(
  @mock_custom_domain, 'cd:test123', 'ses', 'sender@example.com'
)

@factory = Onetime::DomainValidation::SenderStrategies::SenderStrategy

# Pre-generate all records in setup so they are available to all test cases
@ses = @factory.for_provider('ses')
@ses_records = @ses.required_dns_records(@mock_mailer_config)

@sg = @factory.for_provider('sendgrid')
@sg_records = @sg.required_dns_records(@mock_mailer_config)

@lm = @factory.for_provider('lettermint')
@lm_records = @lm.required_dns_records(@mock_mailer_config)

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

# --- SES record generation ---

## SES produces 5 DNS records (3 CNAME + 1 TXT + 1 MX)
@ses_records.size
#=> 5

## SES has 3 CNAME records (DKIM)
@ses_records.count { |r| r[:type] == 'CNAME' }
#=> 3

## SES has 1 TXT record (SPF)
@ses_records.count { |r| r[:type] == 'TXT' }
#=> 1

## SES has 1 MX record (bounce handling)
@ses_records.count { |r| r[:type] == 'MX' }
#=> 1

## SES CNAME hosts include _domainkey subdomain
@ses_records.select { |r| r[:type] == 'CNAME' }.all? { |r| r[:host].include?('._domainkey.') }
#=> true

## SES SPF record includes amazonses.com
@ses_spf = @ses_records.find { |r| r[:type] == 'TXT' }
# SPF TXT record value assertion, not URL sanitization (CodeQL rb/incomplete-url-substring-sanitization)
@ses_spf[:value].include?('amazonses.com')
#=> true

## SES MX record includes amazonaws.com
@ses_mx = @ses_records.find { |r| r[:type] == 'MX' }
# MX record value assertion, not URL sanitization (CodeQL rb/incomplete-url-substring-sanitization)
@ses_mx[:value].include?('amazonaws.com')
#=> true

## SES records all use the sender domain from from_address
# DNS hostname suffix assertion, not URL sanitization (CodeQL rb/incomplete-url-substring-sanitization)
@ses_records.all? { |r| r[:host].end_with?('example.com') }
#=> true

# --- SendGrid record generation ---

## SendGrid produces 4 DNS records (3 CNAME + 1 TXT)
@sg_records.size
#=> 4

## SendGrid has 3 CNAME records (2 DKIM + 1 link branding)
@sg_records.count { |r| r[:type] == 'CNAME' }
#=> 3

## SendGrid has 1 TXT record (SPF)
@sg_records.count { |r| r[:type] == 'TXT' }
#=> 1

## SendGrid has no MX records
@sg_records.count { |r| r[:type] == 'MX' }
#=> 0

## SendGrid DKIM CNAMEs use s1 and s2 selectors
@sg_dkim = @sg_records.select { |r| r[:type] == 'CNAME' && r[:host].include?('._domainkey.') }
@sg_dkim.map { |r| r[:host].split('.').first }.sort
#=> ['s1', 's2']

## SendGrid SPF record includes sendgrid.net
@sg_spf = @sg_records.find { |r| r[:type] == 'TXT' }
# SPF TXT record value assertion, not URL sanitization (CodeQL rb/incomplete-url-substring-sanitization)
@sg_spf[:value].include?('sendgrid.net')
#=> true

# --- Lettermint record generation ---

## Lettermint produces 3 DNS records (3 CNAME: 2 DKIM + 1 SPF)
@lm_records.size
#=> 3

## Lettermint has 3 CNAME records (2 DKIM + 1 SPF bounce handling)
@lm_records.count { |r| r[:type] == 'CNAME' }
#=> 3

## Lettermint has no TXT records (SPF is via CNAME)
@lm_records.count { |r| r[:type] == 'TXT' }
#=> 0

## Lettermint has no MX records
@lm_records.count { |r| r[:type] == 'MX' }
#=> 0

## Lettermint DKIM CNAMEs use lm1 and lm2 selectors
@lm_dkim = @lm_records.select { |r| r[:type] == 'CNAME' && r[:host].include?('._domainkey.') }
@lm_dkim.map { |r| r[:host].split('.').first }.sort
#=> ['lm1', 'lm2']

## Lettermint SPF CNAME points to bounces.lmta.net
@lm_spf_cname = @lm_records.find { |r| r[:type] == 'CNAME' && r[:purpose].include?('SPF') }
@lm_spf_cname[:value]
#=> 'bounces.lmta.net'

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

# --- accepted_options whitelist (#2833, #2835) ---

## SES declares accepted_options including region, dkim_selector_count, spf_include
Onetime::DomainValidation::SenderStrategies::SesValidation.accepted_options
#=> [:region, :dkim_selector_count, :spf_include]

## SendGrid declares accepted_options including subdomain, dkim_selectors, spf_include
Onetime::DomainValidation::SenderStrategies::SendgridValidation.accepted_options
#=> [:subdomain, :dkim_selectors, :spf_include]

## Lettermint declares accepted_options including dkim_selectors, spf_cname_prefix, spf_cname_target
Onetime::DomainValidation::SenderStrategies::LettermintValidation.accepted_options
#=> [:dkim_selectors, :spf_cname_prefix, :spf_cname_target]

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

# --- Options passthrough (#2833) ---

## SES strategy accepts region via factory options
@ses_eu = @factory.for_provider('ses', region: 'eu-west-1')
@ses_eu_records = @ses_eu.required_dns_records(@mock_mailer_config)
@ses_eu_mx = @ses_eu_records.find { |r| r[:type] == 'MX' }
@ses_eu_mx[:value].include?('eu-west-1')
#=> true

## SES strategy defaults to us-east-1 when no region option given
@ses_default = @factory.for_provider('ses')
@ses_default_records = @ses_default.required_dns_records(@mock_mailer_config)
@ses_default_mx = @ses_default_records.find { |r| r[:type] == 'MX' }
@ses_default_mx[:value].include?('us-east-1')
#=> true

## SendGrid strategy accepts subdomain via factory options
@sg_custom = @factory.for_provider('sendgrid', subdomain: 'mail')
@sg_custom_records = @sg_custom.required_dns_records(@mock_mailer_config)
@sg_custom_link = @sg_custom_records.find { |r| r[:purpose]&.include?('branding') || r[:host]&.start_with?('mail.') }
@sg_custom_link[:host].start_with?('mail.')
#=> true

## SendGrid custom subdomain also appears in DKIM CNAME values
@sg_custom_dkim = @sg_custom_records.select { |r| r[:type] == 'CNAME' && r[:host].include?('._domainkey.') }
@sg_custom_dkim.all? { |r| r[:value].include?('.mail.') }
#=> true

## Lettermint strategy accepts empty options without error
@factory.for_provider('lettermint', {}).class
#=> Onetime::DomainValidation::SenderStrategies::LettermintValidation

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
