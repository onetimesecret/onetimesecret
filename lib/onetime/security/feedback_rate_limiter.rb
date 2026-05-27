# lib/onetime/security/feedback_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # FeedbackRateLimiter - Prevents feedback endpoint abuse
    #
    # Tracks feedback submissions per IP address using Redis.
    # After MAX_SUBMISSIONS within RATE_WINDOW, further submissions
    # are rejected for LOCKOUT_DURATION.
    #
    # Redis keys:
    #   - feedback:submissions:{ip} - Counter (expires with RATE_WINDOW)
    #   - feedback:locked:{ip}      - Lockout flag (expires with LOCKOUT_DURATION)
    #
    # Usage:
    #   include Onetime::Security::FeedbackRateLimiter
    #
    #   # In raise_concerns:
    #   check_feedback_rate_limit!(client_ip)
    #
    #   # After successful submission:
    #   record_feedback_submission!(client_ip)
    #
    module FeedbackRateLimiter
      # Maximum submissions per IP within the rate window
      MAX_SUBMISSIONS = 10

      # Window in seconds for counting submissions (1 hour)
      RATE_WINDOW = 3600

      # Lockout duration after exceeding limit (1 hour)
      LOCKOUT_DURATION = 3600

      # Lua script to atomically increment submissions and handle expiration/lockout
      RECORD_SUBMISSION_SCRIPT = <<~LUA
        local submissions_key = KEYS[1]
        local lockout_key = KEYS[2]
        local rate_window = tonumber(ARGV[1])
        local max_submissions = tonumber(ARGV[2])
        local lockout_duration = tonumber(ARGV[3])

        local current = redis.call('INCR', submissions_key)

        if current == 1 then
          redis.call('EXPIRE', submissions_key, rate_window)
        end

        if current >= max_submissions then
          redis.call('SETEX', lockout_key, lockout_duration, '1')
          redis.call('DEL', submissions_key)
        end

        return current
      LUA

      # Check if feedback submissions are rate limited for an IP.
      # Raises LimitExceeded if the IP is locked out due to too many submissions.
      #
      # @param ip_address [String] The submitter's IP address
      # @raise [Onetime::LimitExceeded] If rate limit is exceeded
      # @return [void]
      def check_feedback_rate_limit!(ip_address)
        return if ip_address.to_s.empty?

        lockout_key     = feedback_lockout_key(ip_address)
        submissions_key = feedback_submissions_key(ip_address)

        # Batch operations to avoid multiple Redis network trips
        is_locked, ttl, current = feedback_redis.pipelined do |pipe|
          pipe.exists?(lockout_key)
          pipe.ttl(lockout_key)
          pipe.get(submissions_key)
        end

        # Handle different redis-rb version return types for exists?
        if [true, 1].include?(is_locked)
          raise Onetime::LimitExceeded.new(
            'Too many feedback submissions. Please try again later.',
            error_key: 'api.feedback.errors.rate_limit_exceeded',
            retry_after: ttl > 0 ? ttl : LOCKOUT_DURATION,
            max_attempts: MAX_SUBMISSIONS,
          )
        end

        current = current.to_i

        # Log if approaching limit (for monitoring)
        if current >= MAX_SUBMISSIONS - 2
          OT.li "[FeedbackRateLimiter] IP #{obscured_ip(ip_address)} at #{current}/#{MAX_SUBMISSIONS} submissions"
        end
      end

      # Record a feedback submission for an IP.
      # After MAX_SUBMISSIONS, creates a lockout that blocks further submissions.
      #
      # @param ip_address [String] The submitter's IP address
      # @return [Integer] Current submission count after increment
      def record_feedback_submission!(ip_address)
        return 0 if ip_address.to_s.empty?

        submissions_key = feedback_submissions_key(ip_address)
        lockout_key     = feedback_lockout_key(ip_address)

        # Atomically increment and set TTLs via Lua script
        current = feedback_redis.eval(
          RECORD_SUBMISSION_SCRIPT,
          keys: [submissions_key, lockout_key],
          argv: [RATE_WINDOW, MAX_SUBMISSIONS, LOCKOUT_DURATION],
        )

        if current >= MAX_SUBMISSIONS
          OT.le "[FeedbackRateLimiter] IP #{obscured_ip(ip_address)} locked for #{LOCKOUT_DURATION}s after #{current} submissions"
        end

        current
      end

      # Clear rate limit state for an IP (admin / colonel reset path)
      #
      # @param ip_address [String] The submitter's IP address
      # @return [void]
      def clear_feedback_rate_limit!(ip_address)
        return if ip_address.to_s.empty?

        feedback_redis.del(
          feedback_submissions_key(ip_address),
          feedback_lockout_key(ip_address),
        )
      end

      private

      def feedback_submissions_key(ip_address)
        "feedback:submissions:#{ip_address}"
      end

      def feedback_lockout_key(ip_address)
        "feedback:locked:#{ip_address}"
      end

      # Obscure the IP for logs so we don't store full client addresses
      # in operational output. IPv4 keeps the /16; IPv6 keeps the first
      # nine characters (roughly the routed prefix).
      def obscured_ip(ip_address)
        parts = ip_address.to_s.split('.')
        if parts.length == 4
          "#{parts[0]}.#{parts[1]}.x.x"
        else
          ip_address.to_s[0..8]
        end
      end

      # Access to Redis connection via Feedback model's dbclient.
      # Familia::Horreum exposes dbclient the same way as Secret/CustomDomain,
      # so submissions and lockouts live on the same shard as the feedback
      # store itself.
      def feedback_redis
        Onetime::Feedback.dbclient
      end
    end
  end
end
