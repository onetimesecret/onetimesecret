# try/unit/boot/check_secret_verifier_try.rb
#
# frozen_string_literal: true

# Boot-time SECRET verifier (C10/QS-6): Onetime::SecretVerifier binds the
# running SECRET to the data it encrypted via an HKDF-derived verifier stored
# in the datastore. These tryouts drive the four check! states against the
# real test Valkey, the read-only status used by rake ots:secrets:verify, and
# the CheckSecretVerifier initializer's warn/enforce/off policy.

require_relative '../../support/test_models'

OT.boot! :test, true

VERIFIER_KEY = Onetime::SecretVerifier::VERIFIER_KEY
@expected    = Onetime::SecretVerifier.expected_verifier

## expected_verifier is the hex :key_verifier derivation of site.secret
@expected == Onetime::KeyDerivation.derive_hex(OT.conf.dig('site', 'secret'), :key_verifier)
#=> true

## Absent key: check! adopts (SET NX), stores the expected value, caches state
Familia.dbclient.del(VERIFIER_KEY)
state = Onetime::SecretVerifier.check!
[state, Onetime.secret_verifier_state, Familia.dbclient.get(VERIFIER_KEY) == @expected]
#=> [:adopted, :adopted, true]

## Present and equal: check! reports :ok
Onetime::SecretVerifier.check!
#=> :ok

## Present and different: check! reports :mismatch and never overwrites
Familia.dbclient.set(VERIFIER_KEY, 'not-the-real-verifier')
state = Onetime::SecretVerifier.check!
[state, Onetime.secret_verifier_state, Familia.dbclient.get(VERIFIER_KEY)]
#=> [:mismatch, :mismatch, 'not-the-real-verifier']

## Datastore unreachable: check! degrades to :unavailable, never raises
class << Onetime::SecretVerifier
  alias_method :orig_stored_verifier, :stored_verifier
  def stored_verifier = raise 'connection refused'
end
state = Onetime::SecretVerifier.check!
class << Onetime::SecretVerifier
  alias_method :stored_verifier, :orig_stored_verifier
  remove_method :orig_stored_verifier
end
[state, Onetime.secret_verifier_state]
#=> [:unavailable, :unavailable]

## Read-only status: reports :mismatch without adopting or repairing
Familia.dbclient.set(VERIFIER_KEY, 'not-the-real-verifier')
[Onetime::SecretVerifier.status, Familia.dbclient.get(VERIFIER_KEY)]
#=> [:mismatch, 'not-the-real-verifier']

## Read-only status: absent key reports :unadopted and does NOT adopt
Familia.dbclient.del(VERIFIER_KEY)
[Onetime::SecretVerifier.status, Familia.dbclient.get(VERIFIER_KEY)]
#=> [:unadopted, nil]

## adopt! unconditionally re-stamps the verifier for the running SECRET
Familia.dbclient.set(VERIFIER_KEY, 'stale-verifier-from-old-secret')
Onetime::SecretVerifier.adopt!
[Familia.dbclient.get(VERIFIER_KEY) == @expected, Onetime.secret_verifier_state, Onetime::SecretVerifier.status]
#=> [true, :ok, :ok]

## Policy mode defaults to warn when unset or unrecognized
@original_mode = OT.conf['site']['secret_verifier_mode']
OT.conf['site']['secret_verifier_mode'] = 'bogus'
mode_bogus = Onetime::SecretVerifier.mode
OT.conf['site'].delete('secret_verifier_mode')
mode_unset = Onetime::SecretVerifier.mode
OT.conf['site']['secret_verifier_mode'] = @original_mode
[mode_bogus, mode_unset]
#=> ['warn', 'warn']

## Initializer with warn mode logs but keeps booting on mismatch
Familia.dbclient.set(VERIFIER_KEY, 'not-the-real-verifier')
OT.conf['site']['secret_verifier_mode'] = 'warn'
result = Onetime::Initializers::CheckSecretVerifier.new.execute(nil)
[Onetime.secret_verifier_state, result.nil?]
#=> [:mismatch, true]

## Initializer with enforce mode raises SecretVerifierMismatch (FatalBootError)
Familia.dbclient.set(VERIFIER_KEY, 'not-the-real-verifier')
OT.conf['site']['secret_verifier_mode'] = 'enforce'
error = begin
  Onetime::Initializers::CheckSecretVerifier.new.execute(nil)
  nil
rescue Onetime::SecretVerifierMismatch => ex
  ex
end
[error.class, error.is_a?(Onetime::FatalBootError)]
#=> [Onetime::SecretVerifierMismatch, true]

## Initializer with off mode is skipped entirely
OT.conf['site']['secret_verifier_mode'] = 'off'
Onetime::Initializers::CheckSecretVerifier.new.should_skip?
#=> true

# Teardown: restore the real verifier and a clean state for other tryouts.
OT.conf['site']['secret_verifier_mode'] = @original_mode
Onetime::SecretVerifier.adopt!
