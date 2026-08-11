# apps/api/domains/try/logic/config_change_logger_try.rb
#
# frozen_string_literal: true

# Tests for the shared ConfigChangeLogger change-computation machinery
# used by the per-config ChangeLogger modules (SsoConfig, SenderConfig,
# SignupConfig, SigninConfig).
#
# Covers compute_config_changes:
#   - safe fields log from/to values; unchanged fields are omitted
#   - boolean fields read the old value via the config's predicate method
#     and tolerate a config that lacks the predicate (no NoMethodError)
#   - nil and '' normalize to the same bucket, so nil -> '' is no-change
#   - arrays compare order- and case-insensitively
#   - sensitive fields log {changed: true} only, never values

require_relative '../../../../../try/support/test_helpers'

OT.boot! :test

require 'apps/api/domains/logic/config_change_logger'

# Harness exposing the module's private methods for direct testing.
class ChangeLoggerHarness
  include DomainsAPI::Logic::ConfigChangeLogger

  def compute(...)
    compute_config_changes(...)
  end
end

# Config with a boolean predicate and plain readers.
class FullFakeConfig
  def enabled? = false
  def provider = 'okta'
  def contact  = nil
end

# Config missing the boolean predicate and the plain reader.
class BareFakeConfig
end

# Config with an array-valued field.
class ArrayFakeConfig
  def domains = ['B.example.com', 'a.example.com']
end

@harness = ChangeLoggerHarness.new
@full    = FullFakeConfig.new
@bare    = BareFakeConfig.new

# TRYOUTS

## Changed safe field records from/to values
@harness.compute(@full, { 'provider' => 'entra' }, safe_fields: ['provider'])
#=> { 'provider' => { from: 'okta', to: 'entra' } }

## Unchanged safe field is omitted
@harness.compute(@full, { 'provider' => 'okta' }, safe_fields: ['provider'])
#=> {}

## Field absent from params is omitted even when values differ
@harness.compute(@full, {}, safe_fields: ['provider'])
#=> {}

## Symbol param keys are recognized too
@harness.compute(@full, { provider: 'entra' }, safe_fields: ['provider'])
#=> { 'provider' => { from: 'okta', to: 'entra' } }

## Boolean field reads old value via predicate and coerces new value
@harness.compute(@full, { 'enabled' => 'true' }, safe_fields: ['enabled'], boolean_fields: ['enabled'])
#=> { 'enabled' => { from: false, to: true } }

## Boolean coercion: only true/'true'/'1'/1 are truthy
@harness.compute(@full, { 'enabled' => 'yes' }, safe_fields: ['enabled'], boolean_fields: ['enabled'])
#=> {}

## Config lacking the boolean predicate yields nil old value, no NoMethodError
@harness.compute(@bare, { 'enabled' => 'true' }, safe_fields: ['enabled'], boolean_fields: ['enabled'])
#=> { 'enabled' => { from: nil, to: true } }

## Config lacking a plain reader yields nil old value
@harness.compute(@bare, { 'provider' => 'okta' }, safe_fields: ['provider'])
#=> { 'provider' => { from: nil, to: 'okta' } }

## nil -> '' is treated as no-change (documented normalize_value collapse)
@harness.compute(@full, { 'contact' => '' }, safe_fields: ['contact'])
#=> {}

## Arrays compare order- and case-insensitively
@harness.compute(ArrayFakeConfig.new, { 'domains' => ['A.EXAMPLE.COM', 'b.example.com'] }, safe_fields: ['domains'])
#=> {}

## Sensitive field records changed-only, never the value
@harness.compute(@full, { 'client_secret' => 'hunter2' }, safe_fields: [], sensitive_fields: ['client_secret'])
#=> { 'client_secret' => { changed: true } }

## Blank sensitive field is not recorded
@harness.compute(@full, { 'client_secret' => '   ' }, safe_fields: [], sensitive_fields: ['client_secret'])
#=> {}
