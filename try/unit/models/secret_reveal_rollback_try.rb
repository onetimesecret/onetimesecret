# try/unit/models/secret_reveal_rollback_try.rb
#
# frozen_string_literal: true

# C10/QS-6: a wrong-key decrypt must not burn the secret.
#
# Secret#reveal! persists the atomic reveal claim (win_reveal_claim!, CAS
# new/previewed -> revealed) BEFORE decrypting. Without rollback, a decrypt
# that raises Familia::EncryptionError (SECRET changed under existing data)
# leaves state=revealed -- terminal -- while the ciphertext survives:
# restoring the correct SECRET could never un-burn it.
#
# reveal! now rolls the claim back on Familia::EncryptionError: zero
# plaintext was produced, so returning the claim cannot violate ADR-019's
# at-most-once display, and only the claim holder can be in :revealed, so
# the CAS back cannot race another winner. The typed error
# Onetime::SecretUndecryptable propagates to the HTTP edge as a 503.
#
# See secret_double_reveal_race_try.rb for the claim/race semantics these
# tryouts must not weaken.

require_relative '../../support/test_models'

OT.boot! :test, true

# Simulate the wrong-key condition on a single loaded instance: decryption
# raises exactly where Familia's encrypted-field reveal would.
def stub_wrong_key!(secret_instance)
  def secret_instance.decrypted_secret_value(**)
    raise Familia::EncryptionError, 'decryption failed: wrong key'
  end
end

## A wrong-key decrypt raises SecretUndecryptable and rolls the claim back:
## persisted state returns to the pre-claim value and the in-memory instance
## agrees.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'still encrypted'
s = Onetime::Secret.load(secret.identifier)
stub_wrong_key!(s)
error = begin
  s.reveal!
  nil
rescue Onetime::SecretUndecryptable => ex
  ex
end
fresh = Onetime::Secret.load(secret.identifier)
[error.class, s.state, fresh.state]
#=> [Onetime::SecretUndecryptable, 'new', 'new']

## The record and its ciphertext survive the failed reveal (nothing consumed,
## nothing cleared) -- the secret is still viewable once the key returns.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'still encrypted'
s = Onetime::Secret.load(secret.identifier)
stub_wrong_key!(s)
begin
  s.reveal!
rescue Onetime::SecretUndecryptable
  # expected
end
fresh = Onetime::Secret.load(secret.identifier)
[fresh.exists?, fresh.key?(:ciphertext), fresh.viewable?]
#=> [true, true, true]

## After the key is restored (un-stubbed instance), reveal! succeeds exactly
## as if the failed attempt never happened: plaintext returned, secret consumed.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'recovered plaintext'
s1 = Onetime::Secret.load(secret.identifier)
stub_wrong_key!(s1)
begin
  s1.reveal!
rescue Onetime::SecretUndecryptable
  # expected
end
s2 = Onetime::Secret.load(secret.identifier)
plaintext = s2.reveal!
[plaintext, s2.exists?]
#=> ['recovered plaintext', false]

## Rollback restores the actual pre-claim state, not a hardcoded 'new':
## a previewed secret rolls back to 'previewed'.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'still encrypted'
secret.state = 'previewed'
secret.save_fields(:state)
s = Onetime::Secret.load(secret.identifier)
stub_wrong_key!(s)
begin
  s.reveal!
rescue Onetime::SecretUndecryptable
  # expected
end
[s.state, Onetime::Secret.load(secret.identifier).state]
#=> ['previewed', 'previewed']

## Race semantics are unchanged: a concurrent caller inside the winner's
## claim-held window (after the CAS, before the rollback) still loses and
## gets nil, and a caller arriving AFTER the rollback can win cleanly -- a
## legal sequence because zero plaintexts were displayed.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race with rollback'
winner       = Onetime::Secret.load(secret.identifier)
loser        = Onetime::Secret.load(secret.identifier)
loser_result = :unset
winner.define_singleton_method(:decrypted_secret_value) do |**|
  # The claim is held right here (state=revealed in Redis): a racing reveal
  # must lose the CAS and return nil.
  loser_result = loser.reveal!
  raise Familia::EncryptionError, 'wrong key'
end
begin
  winner.reveal!
rescue Onetime::SecretUndecryptable
  # expected
end
late_caller = Onetime::Secret.load(secret.identifier)
[loser_result, late_caller.reveal!, late_caller.exists?]
#=> [nil, 'race with rollback', false]

## revealed! (consume-without-decrypt) is deliberately untouched by rollback:
## it never decrypts, so it cannot hit the wrong-key path. (v1 decrypts
## before claiming and is incidentally non-destructive already.)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'consumed blind'
s = Onetime::Secret.load(secret.identifier)
[s.revealed!, s.exists?]
#=> [true, false]
