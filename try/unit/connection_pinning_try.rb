# try/unit/connection_pinning_try.rb
#
# frozen_string_literal: true

# Covers Onetime.with_pinned_dbclient and the pinned-path branch of the
# connection_provider lambda. The helper exists so that WATCH/MULTI and
# other multi-step coherence flows can guarantee every Familia.dbclient
# call on the current fiber resolves to one socket; without it the
# provider's pool.with-and-release pattern hands out fresh checkouts.

require_relative '../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for connection pinning tests"

## Helper is defined on Onetime
Onetime.respond_to?(:with_pinned_dbclient)
#=> true

## Missing block raises ArgumentError
begin
  Onetime.with_pinned_dbclient
  :no_raise
rescue ArgumentError => ex
  ex.message
end
#=> 'Block required for with_pinned_dbclient'

## Pin resolves repeated Familia.dbclient calls to the same object
@same_conn_result = Onetime.with_pinned_dbclient do |conn|
  [conn.object_id == Familia.dbclient.object_id,
   Familia.dbclient.object_id == Familia.dbclient.object_id]
end
@same_conn_result
#=> [true, true]

## Pin clears the fiber stack on normal block exit
Onetime.with_pinned_dbclient { |_| :ok }
Fiber[:ots_pinned_dbclient_stack]
#=> nil

## Reentrancy: nested call reuses outer conn, no second checkout
@reentrant_ids = Onetime.with_pinned_dbclient do |outer|
  Onetime.with_pinned_dbclient do |inner|
    [outer.object_id, inner.object_id]
  end
end
@reentrant_ids[0] == @reentrant_ids[1]
#=> true

## Reentrancy does not push duplicate frames onto the stack
@stack_depth = Onetime.with_pinned_dbclient do |_|
  depth_outer = Fiber[:ots_pinned_dbclient_stack].size
  depth_inner = Onetime.with_pinned_dbclient { |_| Fiber[:ots_pinned_dbclient_stack].size }
  [depth_outer, depth_inner]
end
@stack_depth
#=> [1, 1]

## Exception inside pin propagates and still clears the stack
begin
  Onetime.with_pinned_dbclient { raise 'boom' }
rescue RuntimeError => ex
  @exception_msg = ex.message
end
[@exception_msg, Fiber[:ots_pinned_dbclient_stack]]
#=> ['boom', nil]

## Return from inside the block still cleans up the stack
def pinned_early_return
  Onetime.with_pinned_dbclient { |_| return :early }
end
@early_return_value = pinned_early_return
[@early_return_value, Fiber[:ots_pinned_dbclient_stack]]
#=> [:early, nil]

## Commands issued via Familia.dbclient inside the pin hit the pinned conn
Onetime.with_pinned_dbclient do |conn|
  conn.set('ots:pin:probe', 'hello')
  Familia.dbclient.get('ots:pin:probe')
end
#=> 'hello'

## Pin participates in WATCH/MULTI coherence: MULTI queued via Familia.dbclient
## lands on the pinned conn and sees the earlier WATCH on that same conn.
## Mutating the watched key from a *different* pool connection between WATCH
## and EXEC aborts the transaction — EXEC returns nil, confirming the WATCH
## and MULTI share a socket.
Familia.dbclient.set('ots:pin:watch_target', 'before')
@watch_aborted = Onetime.with_pinned_dbclient do |conn|
  conn.watch('ots:pin:watch_target') do
    # Mutate via a fresh pool connection (the pinned conn is already held,
    # so pool.with checks out a different slot).
    Onetime::Runtime.infrastructure.database_pool.with do |c|
      c.set('ots:pin:watch_target', 'racer')
    end
    Familia.dbclient.multi do |multi|
      multi.set('ots:pin:watch_target', 'after')
    end
  end
end
@watch_aborted.nil?
#=> true

## Final value reflects the racer, not the MULTI that was aborted by WATCH
Familia.dbclient.get('ots:pin:watch_target')
#=> 'racer'

# Teardown
Familia.dbclient.del('ots:pin:probe', 'ots:pin:watch_target')
