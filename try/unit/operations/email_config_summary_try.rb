# try/unit/operations/email_config_summary_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the shared email config summary (ITEM 1 + the items-1/11
# security property):
#   Onetime::Operations::Email::ConfigSummary
#
# This is the SINGLE source of the masked mailer-config view shared by the
# `bin/ots email config` CLI and the colonel GET /api/colonel/email/config
# endpoint. Covers:
# - build returns the full contract shape: provider / auto_detected /
#   from_address / from_name / provider_config / sender_provider / sender_differs
# - sender_differs is a boolean == (sender_provider != provider)
# - provider_config is the STABLE six-key superset with has_credentials boolean
# - NO-CREDS-IN-PAYLOAD: a deep scan of build's output contains no secret, and
#   masked_provider_config on an SMTP config with user/pass emits neither
#
# Run: try --agent try/unit/operations/email_config_summary_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/email/config_summary'

CS = Onetime::Operations::Email::ConfigSummary

# ---- build: shape ------------------------------------------------------

## build returns a Hash with every contract key
@summary = CS.build
%i[provider auto_detected from_address from_name provider_config sender_provider sender_differs].all? { |k| @summary.key?(k) }
#=> true

## provider is a non-empty string (test env resolves to 'logger')
@summary = CS.build
@summary[:provider].is_a?(String) && !@summary[:provider].empty?
#=> true

## auto_detected is a boolean
@summary = CS.build
[true, false].include?(@summary[:auto_detected])
#=> true

## sender_differs is a boolean equal to (sender_provider != provider)
@summary = CS.build
@summary[:sender_differs] == (@summary[:sender_provider] != @summary[:provider])
#=> true

# ---- provider_config: stable superset ----------------------------------

## provider_config always carries exactly the six superset keys
@summary = CS.build
@summary[:provider_config].keys.sort
#=> %i[domain has_credentials host port region tls].sort

## has_credentials is always a boolean
@summary = CS.build
[true, false].include?(@summary[:provider_config][:has_credentials])
#=> true

# ---- masked_provider_config: SMTP creds never emitted ------------------

## an SMTP config with user/pass yields has_credentials true and no secret keys
@smtp = CS.masked_provider_config('smtp', {
  'host' => 'smtp.example.com', 'port' => '587', 'domain' => 'example.com',
  'tls' => true, 'user' => 'smtp-user', 'pass' => 'super-secret-pw',
})
[@smtp[:has_credentials], @smtp.key?(:user), @smtp.key?(:pass), @smtp[:host], @smtp[:port]]
#=> [true, false, false, 'smtp.example.com', 587]

## port is coerced from a string to an Integer
CS.coerce_port('2525')
#=> 2525

## a nil / blank / non-numeric port coerces to nil (never a raw string)
[CS.coerce_port(nil), CS.coerce_port('   '), CS.coerce_port('not-a-port')]
#=> [nil, nil, nil]

## an explicit config port wins over the env fallback and is an Integer
CS.masked_provider_config('smtp', { 'host' => 'h', 'port' => '2525' })[:port]
#=> 2525

## an SES config with AWS creds yields region + has_credentials, no secrets
@ses = CS.masked_provider_config('ses', {
  'region' => 'us-east-1', 'user' => 'AKIAEXAMPLE', 'pass' => 'aws-secret-key',
})
[@ses[:region], @ses[:has_credentials], @ses.key?(:user), @ses.key?(:pass)]
#=> ['us-east-1', true, false, false]

## logger/unknown provider yields the bare superset with no credentials
@none = CS.masked_provider_config('logger', {})
[@none[:has_credentials], @none[:host], @none[:region]]
#=> [false, nil, nil]

# ---- NO-CREDS-IN-PAYLOAD: scan of build --------------------------------
#
# provider_config is the only nested hash and its values are all scalars, so
# every leaf value = top-level values + provider_config values.

## build's leaf values contain none of the secret sentinels an operator might set
@summary = CS.build
@leaves  = (@summary.values + @summary[:provider_config].values).compact.map(&:to_s)
%w[super-secret-pw aws-secret-key sendgrid-key some-token].any? do |secret|
  @leaves.any? { |v| v.include?(secret) }
end
#=> false

## build carries no key whose NAME implies a secret (user/pass/secret/key/token)
@summary = CS.build
@keys    = @summary.keys.map(&:to_s) + @summary[:provider_config].keys.map(&:to_s)
@keys.any? { |k| k.match?(/user|pass|secret|token/i) || k == 'api_key' }
#=> false
