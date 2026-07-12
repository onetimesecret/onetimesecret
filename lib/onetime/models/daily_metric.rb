# lib/onetime/models/daily_metric.rb
#
# frozen_string_literal: true

module Onetime
  # DailyMetric — cheap per-day activity counters for the admin dashboard.
  #
  # Answers "is today weird?" for the colonel overview: every lifetime counter
  # (Customer.secrets_created etc.) only ever goes up and every other stat is a
  # right-now total, so nothing shows day-over-day shape. This model keeps one
  # plain Redis string counter per metric per UTC day:
  #
  #   daily_metric:<metric>:<YYYYMMDD>
  #
  # ## Write path (fire-and-forget)
  #
  # `increment` is called from hot host operations (customer signup, secret
  # creation) and must NEVER be able to fail them: the INCR+EXPIRE runs as one
  # atomic Lua script (the error_handler.rb daily-counter precedent — no
  # crash-window between the two commands leaving a permanent key) and any
  # error is logged and swallowed. A lost tick costs one point on a sparkline,
  # never a signup or a secret.
  #
  # ## Retention
  #
  # Each day-key expires ~90 days after its first increment, so the store is
  # self-pruning and bounded to one small key per metric per day — no cap
  # bookkeeping, no scheduled cleanup.
  #
  # ## Read path
  #
  # `counts` zero-fills days with no key (MGET returns nil for them), so the
  # series always spans the full window. Collection is forward-only: there is
  # no backfill source (see GetColonelStats' backfill note), days before the
  # instrumentation shipped simply read 0 and the UI says so.
  class DailyMetric
    # Metrics currently collected (documentation + spec guard, not enforced —
    # the key space is namespaced per metric either way).
    METRICS = %w[signups secrets_created].freeze

    # Per-day-key retention. ~90 days keeps a quarter of history (3x the
    # 30-day dashboard window) while staying self-pruning.
    RETENTION_TTL = 90 * 24 * 60 * 60

    KEY_PREFIX = 'daily_metric'

    # Atomic INCR + EXPIRE (mirrors Onetime::ErrorHandler::TRACK_ERROR_LUA):
    # a crash between the two commands would otherwise leave a permanent key.
    INCREMENT_LUA = <<~LUA
      local c = redis.call('INCR', KEYS[1])
      if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
      return c
    LUA

    class << self
      # Count one occurrence of `metric` in today's (UTC) bucket.
      #
      # Fire-and-forget by contract: any failure is logged and swallowed so
      # the calling operation (signup, secret creation) can never be broken
      # by metrics collection.
      #
      # @param metric [String, Symbol] metric name, e.g. :signups
      # @param time [Time] bucket timestamp (defaults to now; UTC-bucketed)
      # @return [Integer, nil] the new count, or nil if the write failed
      def increment(metric, time = Time.now)
        key = key_for(metric, time.utc.to_date)
        Familia.dbclient.eval(INCREMENT_LUA, keys: [key], argv: [RETENTION_TTL])
      rescue StandardError => ex
        OT.le('[DailyMetric] increment failed', exception: ex, metric: metric.to_s)
        nil
      end

      # Per-day counts for the trailing `days` window, oldest first, ending
      # with today (UTC). Days with no data are zero-filled, so the series
      # always has exactly `days` points.
      #
      # @param metric [String, Symbol] metric name, e.g. :signups
      # @param days [Integer] window length in days (today inclusive)
      # @return [Array<Hash>] [{ date: 'YYYY-MM-DD', count: Integer }, ...]
      def counts(metric, days = 30)
        days  = days.to_i
        return [] if days <= 0

        today = Time.now.utc.to_date
        dates = (0...days).map { |offset| today - (days - 1 - offset) }
        keys  = dates.map { |date| key_for(metric, date) }

        values = Familia.dbclient.mget(*keys)
        dates.each_with_index.map do |date, idx|
          { date: date.iso8601, count: values[idx].to_i }
        end
      end

      # @param metric [String, Symbol]
      # @param date [Date] UTC calendar day
      # @return [String] the Redis key for that metric-day bucket
      def key_for(metric, date)
        "#{KEY_PREFIX}:#{metric}:#{date.strftime('%Y%m%d')}"
      end
    end
  end
end
