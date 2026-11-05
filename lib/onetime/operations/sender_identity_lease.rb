# frozen_string_literal: true

module Onetime
  module Operations
    # Keeps the existing Familia lock alive while a synchronous provider call
    # blocks. Loss is sticky: never reacquire and continue another owner's work.
    # Checkpoints stop subsequent local/provider steps, but cannot fence a remote
    # request already in flight when Redis becomes unavailable or the lease expires.
    class SenderIdentityLease
      TTL            = 60
      RENEW_INTERVAL = 20
      RENEW_SCRIPT   = <<~LUA
        if redis.call('get', KEYS[1]) == ARGV[1] then
          return redis.call('expire', KEYS[1], ARGV[2])
        end
        return 0
      LUA

      class Lost < StandardError; end

      def initialize(lock)
        @lock    = lock
        @mutex   = Mutex.new
        @wake    = ConditionVariable.new
        @stopped = false
      end

      def acquire
        started   = monotonic_now
        @token    = @lock.acquire(ttl: TTL)
        @deadline = started + TTL
        @token
      end

      # Must follow a successful acquire. Release only after the renewer has
      # stopped, including on exceptions and nonlocal returns from the block.
      def protect
        @client  = @lock.dbclient
        @key     = @lock.dbkey
        check!
        @renewer = Thread.new do # rubocop:disable ThreadSafety/NewThread -- Renew a lease during blocking provider I/O
          @mutex.synchronize do
            until @stopped || @failure
              @wake.wait(@mutex, RENEW_INTERVAL)
              break if @stopped

              renew
            end
          end
        end
        result   = yield self
        check!
        result
      ensure
        @mutex.synchronize do
          @stopped = true
          @wake.broadcast
        end
        @renewer&.join
        begin
          @lock.release(@token)
        rescue StandardError => ex
          # Do not mask the original failure or a committed destroy's audit.
          # Familia's token check and the TTL still bound cleanup to this owner.
          OT.le "[SenderIdentityLease] Lock release failed: #{ex.class}: #{ex.message}"
        end
      end

      # Renew atomically at step boundaries as well as in the watchdog. A
      # transport error is an ownership uncertainty, not permission to proceed.
      def check!
        @mutex.synchronize do
          renew
          raise @failure if @failure
        end
      end

      private

      def renew
        return if @failure

        started = monotonic_now
        if started >= @deadline
          lose!('local lease deadline elapsed')
        elsif @client.eval(RENEW_SCRIPT, [@key], [@token, TTL]) != 1
          lose!('lock token no longer belongs to this operation')
        elsif monotonic_now >= @deadline
          lose!('renewal response arrived after the lease deadline')
        else
          @deadline = started + TTL
        end
      rescue StandardError => ex
        lose!("renewal failed (#{ex.class}: #{ex.message})")
      end

      def lose!(reason)
        @failure = Lost.new("Sender identity lock lost: #{reason}. Operation stopped; provider state may have changed.")
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
