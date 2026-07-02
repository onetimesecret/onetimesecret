# try/unit/models/secret_double_reveal_race_try.rb
#
# frozen_string_literal: true

# Regression tryouts for the double-reveal race on burn-after-reading secrets.
#
# Burn-after-reading is the core product promise: a secret may be revealed to
# at most ONE caller. Before the atomic guard, two concurrent requests could
# each load the same secret, each observe an in-memory state of :new/:previewed,
# and each pass the guard in revealed!/burned! -- decrypting and destroying in
# lockstep and handing the plaintext to BOTH clients.
#
# revealed!/burned! now perform an atomic compare-and-set in Redis
# (SecretStateManagement#claim_terminal_transition!). Of any number of racing
# callers exactly one wins the claim (returns true); the rest return false and
# the reveal controllers gate the plaintext on that return value.
#
# These tryouts reproduce the race window (two instances that BOTH pass the
# in-memory viewable? check) and assert the atomic outcome.

require_relative '../../support/test_models'

OT.boot! :test, true

## Both loaded instances observe a viewable secret -- the race window exists --
## yet exactly one revealed! wins the atomic claim.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
race_window = [s1.viewable?, s2.viewable?]
results     = [s1.revealed!, s2.revealed!]
[race_window, results.count(true), results.count(false)]
#=> [[true, true], 1, 1]

## After a concurrent reveal the secret is destroyed exactly once.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
r1 = s1.revealed!
r2 = s2.revealed!
[s1.exists?, [r1, r2].count(true)]
#=> [false, 1]

## The winning reveal decrypted the plaintext; the losing caller returns false,
## so its controller never emits the value. (Winner: true, loser: false.)
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'top secret value'
plaintext = Onetime::Secret.load(secret.identifier).decrypted_secret_value
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
r1 = s1.revealed!
r2 = s2.revealed!
[plaintext, r1 ^ r2] # exactly one of r1/r2 is truthy => XOR is true
#=> ['top secret value', true]

## A losing reveal leaves its instance terminal in-memory, so a trailing
## `previewed! if state?(:new)` in the controller cannot resurrect the key the
## winner just destroyed.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
r1    = s1.revealed!
r2    = s2.revealed!
loser = r1 ? s2 : s1
loser.previewed! if loser.state?(:new) # must be a no-op -- would resurrect otherwise
[loser.state?(:new), s1.exists?, s2.exists?]
#=> [false, false, false]

## Concurrent burn: exactly one burned! wins the atomic claim.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
results = [s1.burned!, s2.burned!]
[results.count(true), results.count(false), s1.exists?]
#=> [1, 1, false]

## A reveal racing a burn on the same secret: exactly one wins, and the secret
## is destroyed regardless of which action got there first.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
s1 = Onetime::Secret.load(secret.identifier)
s2 = Onetime::Secret.load(secret.identifier)
revealed = s1.revealed!
burned   = s2.burned!
[[revealed, burned].count(true), s1.exists?]
#=> [1, false]

## True concurrency: many threads race revealed! on separately-loaded
## instances of one secret. Redis executes the Lua claim atomically, so exactly
## one thread wins no matter how the threads interleave.
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'race secret'
instances = Array.new(8) { Onetime::Secret.load(secret.identifier) }
outcomes  = instances.map { |s| Thread.new { s.revealed! } }.map(&:value)
[outcomes.count(true), instances.first.exists?]
#=> [1, false]
