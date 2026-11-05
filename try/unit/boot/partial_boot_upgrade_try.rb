# try/unit/boot/partial_boot_upgrade_try.rb
#
# frozen_string_literal: true

# boot! in test mode: a full boot (connect_to_db=true) after a completed
# partial one (connect_to_db=false) resets and boots fully, instead of
# reusing a state that skipped the database initializers.
#
# Every tryout file in a run shares one process, and tryouts sorts the files
# it is given. Before this, the first file to boot decided for every file
# after it: a partial first boot left configure_familia unrun, and the first
# Secret a later full-boot file created raised KeyError (VERIFIABLE_ID_HMAC_SECRET
# is not set). Running a logic tryout and a model tryout together with
# `tests/lanes/run --only` was enough to hit it.
#
# This file starts from a clean slate and ends on a full boot, the state the
# rest of the run expects.

require_relative '../../support/test_models'

CONFIGURE_FAMILIA = :'onetime.initializers.configure_familia'

def configure_familia_completed?
  OT.boot_registry.initializers.find { |init| init.name == CONFIGURE_FAMILIA }&.completed?
end

OT.reset_all_boot_state!
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
OT.boot! :test, false

## A partial boot completes without the database initializers
[OT.boot_state, OT.boot_connected_to_db?, configure_familia_completed?]
#=> [:started, false, false]

## so the identifier HMAC secret is not derived
ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
#=> nil

## A full boot after it is not skipped: it boots again, and configure_familia runs
@partial_registry = OT.boot_registry
OT.boot! :test
[OT.boot_state, OT.boot_connected_to_db?, configure_familia_completed?, OT.boot_registry.equal?(@partial_registry)]
#=> [:started, true, true, false]

## The identifier HMAC secret is derived again
ENV['VERIFIABLE_ID_HMAC_SECRET'].to_s.empty?
#=> false

## Creating a secret pair mints its identifiers instead of raising KeyError
receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'partial boot upgrade'
minted          = [receipt.identifier, secret.identifier].none? { |id| id.to_s.empty? }
secret.destroy!
receipt.destroy!
minted
#=> true

## A partial boot after a full one reuses the full boot
@full_registry = OT.boot_registry
OT.boot! :test, false
[OT.boot_connected_to_db?, OT.boot_registry.equal?(@full_registry)]
#=> [true, true]

## A repeat full boot reuses it too
OT.boot! :test
[OT.boot_connected_to_db?, OT.boot_registry.equal?(@full_registry)]
#=> [true, true]
