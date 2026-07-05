# try/unit/utils/familia_identifier_secret_try.rb
#
# frozen_string_literal: true

# Verifies that ConfigureFamilia sets a usable VERIFIABLE_ID_HMAC_SECRET so the
# familia >= 2.11 identifier signer (which rejects a missing OR blank secret,
# see delano/familia#335) never crashes at first mint on installs that leave
# IDENTIFIER_SECRET unset or pass it through empty (the compose default
# `IDENTIFIER_SECRET=${IDENTIFIER_SECRET:-}`). See issue #3630.
#
# The fallback derives from site.secret via the same HKDF purpose (:identifier)
# that init.rake writes to .env, so booted-from-init and booted-without-init
# deployments converge on one key.

require_relative '../../support/test_helpers'
require 'onetime/key_derivation'

# connect_to_db=false skips the automatic ConfigureFamilia run, so each case
# below drives the initializer explicitly with the ENV it wants to test.
OT.boot! :test, false

@secret_key = OT.conf.dig('site', 'secret')
@expected_derived = Onetime::KeyDerivation.derive_hex(@secret_key, :identifier)

def run_configure_familia
  Onetime::Initializers::ConfigureFamilia.new.execute({})
end

# reset_secret_key! only exists on familia >= 2.11 (it clears the memoized HMAC
# secret). Guard it so this tryout is green both before and after the 2.11.1
# bump this fix ships alongside.
def reset_verifiable_secret!
  return unless defined?(Familia::VerifiableIdentifier) &&
                Familia::VerifiableIdentifier.respond_to?(:reset_secret_key!)

  Familia::VerifiableIdentifier.reset_secret_key!
end

## The HKDF fallback is a non-empty hex string distinct from a blank value
!@expected_derived.empty? && @expected_derived.match?(/\A[0-9a-f]+\z/)
#=> true

## Unset IDENTIFIER_SECRET: VERIFIABLE_ID_HMAC_SECRET is derived from site.secret
ENV.delete('IDENTIFIER_SECRET')
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
run_configure_familia
ENV['VERIFIABLE_ID_HMAC_SECRET']
#=> @expected_derived

## Blank IDENTIFIER_SECRET (the compose `:-` default) is treated as unset, not
## propagated as an empty HMAC key
ENV['IDENTIFIER_SECRET'] = ''
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
run_configure_familia
ENV['VERIFIABLE_ID_HMAC_SECRET']
#=> @expected_derived

## The derived fallback matches what init.rake would have written to .env, so an
## install that later runs init keeps signing identifiers under the same key
ENV.delete('IDENTIFIER_SECRET')
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
run_configure_familia
ENV['VERIFIABLE_ID_HMAC_SECRET'] == Onetime::KeyDerivation.derive_hex(@secret_key, :identifier)
#=> true

## An explicitly-set IDENTIFIER_SECRET is used verbatim, not overridden by the
## derived fallback
ENV['IDENTIFIER_SECRET'] = 'explicit-operator-provided-identifier-secret'
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
run_configure_familia
ENV['VERIFIABLE_ID_HMAC_SECRET']
#=> 'explicit-operator-provided-identifier-secret'

## The configured secret actually satisfies familia's non-blank guard: minting an
## identifier under it succeeds instead of raising (regression against #3630). On
## familia 2.11+ this exercises the real guard; on 2.10.1 it confirms no
## regression from the still-present committed fallback.
require 'familia/verifiable_identifier'
reset_verifiable_secret!
Familia::VerifiableIdentifier.generate_verifiable_id.is_a?(String)
#=> true

# Leave the process ENV clean for any downstream tooling in the same shell.
ENV.delete('IDENTIFIER_SECRET')
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
reset_verifiable_secret!
