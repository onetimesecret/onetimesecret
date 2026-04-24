# lib/onetime/connection_pinning.rb
#
# frozen_string_literal: true

module Onetime
  # Pin a single database_pool connection to the current fiber for the
  # duration of the block. While pinned, every call to Familia.dbclient
  # resolves to the same connection, so WATCH/MULTI and read-then-write
  # sequences land on one socket.
  #
  # Without pinning, the connection_provider lambda checks out a conn via
  # pool.with and returns it — the conn is back in the pool before the
  # caller uses it. That escaped reference works for single-command
  # callers but silently breaks coherence-sensitive flows: WATCH on one
  # conn has no effect on a MULTI that ends up on a different conn.
  #
  # Reentrant: nested calls on the same fiber reuse the outermost pinned
  # connection and do not check a second connection out of the pool.
  #
  # @yieldparam conn [Redis] the pinned raw Redis connection
  # @return [Object] the block's return value
  # @raise [Onetime::Problem] if the database pool has not been initialized
  def self.with_pinned_dbclient
    raise ArgumentError, 'Block required for with_pinned_dbclient' unless block_given?

    pool = Onetime::Runtime.infrastructure.database_pool
    raise Onetime::Problem, 'Database pool not initialized' unless pool

    stack = (Fiber[:ots_pinned_dbclient_stack] ||= [])

    # Reentrant: reuse the outer pin; no second checkout.
    return yield(stack.last) if stack.any?

    pool.with do |conn|
      stack.push(conn)
      begin
        yield conn
      ensure
        popped = stack.pop
        if popped.equal?(conn)
          Fiber[:ots_pinned_dbclient_stack] = nil if stack.empty?
        else
          # Invariant violated: a nested caller either mutated the stack out
          # of order or the frame was reentered from a different fiber. Clear
          # the fiber-local entirely so subsequent Familia.dbclient calls fall
          # back to a fresh pool checkout rather than reusing a stale conn
          # reference whose pool-with frame has already returned.
          OT.le "[with_pinned_dbclient] stack invariant violated: popped=#{popped.object_id} expected=#{conn.object_id}; clearing fiber stack"
          Fiber[:ots_pinned_dbclient_stack] = nil
        end
      end
    end
  end
end
