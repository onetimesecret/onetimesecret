# lib/onetime/models/delivery_event.rb
#
# frozen_string_literal: true

require_relative '../utils/strings'
require_relative '../operations/email/error_scrub'

module Onetime
  # DeliveryEvent — what the application attempted, and what its own workers
  # observed, for outbound notifications (#4479).
  #
  # One channel-neutral record shape covers email and webhook. It is written
  # at the points where the application hands a notification to something
  # else:
  #
  #   | Channel | Writer               | Stage    | Outcomes                |
  #   |---------|----------------------|----------|-------------------------|
  #   | email   | DispatchNotification | queue    | queued, failed, skipped |
  #   | email   | EmailWorker          | delivery | sent, failed, skipped   |
  #   | webhook | DispatchNotification | delivery | sent, failed, skipped   |
  #
  # `stage` is part of every record so a reader cannot mistake queue
  # acceptance for delivery: `queued` is only valid at stage `queue`, and
  # `sent` only at stage `delivery`.
  #
  # This is not provider deliverability data. Bounces, complaints,
  # suppressions and provider message history stay with
  # Onetime::EmailSuppression and the colonel email deliverability endpoints.
  # `sent` here means the mail backend accepted the message.
  #
  # ## Correlation
  #
  # `correlation_id` is the message id of the source notification on
  # notifications.alert.push. DispatchNotification copies it into the email
  # payload and EmailWorker reads it back, so the queue event and the worker
  # event for one notification share it. `message_id` is the id of the
  # downstream queue message (email.message.send). An email that did not come
  # from a notification has no source id; its worker event uses its own queue
  # message id as the correlation id.
  #
  # ## Retries and duplicates
  #
  # Events are append-only. A worker writes ONE terminal event per processed
  # message, after its in-process retries finish, with `attempt_count`. A
  # redelivered queue message is dropped by the worker's idempotency claim
  # before any event is written. A DLQ replay that is processed again adds a
  # second terminal event under the same correlation id; the newest event for
  # a (correlation_id, channel, stage) is the current state.
  #
  # ## What is stored
  #
  # Identifiers, enums, counts and a scrubbed error message. Never payloads,
  # secret or receipt keys, subjects, bodies, recipient addresses, webhook
  # URLs/paths/queries, or internal object ids. Every field passes through
  # an allowlist pattern or {.scrub_message}; a value that does not fit is
  # dropped rather than stored.
  #
  # ## Backing store
  #
  # - `delivery_event:events` (sorted set): JSON event scored by occurred-at.
  #   Trimmed on every write to MAX_EVENTS and to RETENTION. ZADD and each
  #   trim are single atomic commands; between them the set can exceed the
  #   cap by at most the number of concurrent writers, and a trim never
  #   removes more than the overflow it sees.
  # - `delivery_event:counts:<YYYYMMDD>` (hash): per-day totals keyed
  #   `channel:stage:outcome`, kept COUNTS_TTL. At most 12 fields a day, so
  #   the totals outlive the individual events without growing with volume.
  #
  # Sizing: an event is roughly 300-400 bytes of JSON. 50,000 events is about
  # 20-25 MB at the cap. A notification email writes two events (queue +
  # delivery) and any other email writes one, so the cap holds about five
  # days at 10,000 emails/day and the full retention window below about
  # 3,500/day. These figures are arithmetic, not a production measurement.
  #
  # ## Fail-open
  #
  # {.record} never raises. A failure to build or store an event is logged
  # and returns nil; delivery proceeds as if recording did not exist.
  class DeliveryEvent < Familia::Horreum
    prefix :delivery_event

    # member = JSON event, score = occurred-at epoch seconds (float).
    class_sorted_set :events

    CHANNELS = %w[email webhook].freeze
    STAGES   = %w[queue delivery].freeze
    OUTCOMES = %w[queued sent failed skipped].freeze

    # Outcomes each stage may report.
    STAGE_OUTCOMES = {
      'queue' => %w[queued failed skipped],
      'delivery' => %w[sent failed skipped],
    }.freeze

    MAX_EVENTS = 50_000
    RETENTION  = 14 * 24 * 60 * 60
    COUNTS_TTL = 90 * 24 * 60 * 60

    COUNTS_PREFIX = 'delivery_event:counts'

    MAX_MESSAGE_LENGTH = 200

    # Allowlist shapes. A value that does not match is stored as nil.
    ID_PATTERN          = /\A[\w.:-]{1,128}\z/
    PROVIDER_ID_PATTERN = %r{\A[\w.:@+=/-]{1,200}\z}
    NAME_PATTERN        = /\A[\w.:-]{1,64}\z/
    REASON_PATTERN      = /\A[a-z0-9_]{1,48}\z/
    CLASS_PATTERN       = /\A[\w:]{1,100}\z/
    HOST_PATTERN        = /\A[a-z0-9.:\[\]-]{1,255}\z/
    # Customer external id (Customer's `ur%{id}` format). Anything else —
    # an objid, an email, a legacy custid — is not stored.
    CUSTOMER_ID_PATTERN = /\Aur[0-9a-z]{4,64}\z/

    # Long opaque runs (keys, tokens, identifiers) inside free text.
    OPAQUE_RUN_PATTERN = /[A-Za-z0-9_-]{20,}/

    # Atomic HINCRBY + first-write EXPIRE (the DailyMetric idiom).
    COUNT_LUA = <<~LUA
      local c = redis.call('HINCRBY', KEYS[1], ARGV[1], 1)
      if redis.call('TTL', KEYS[1]) < 0 then redis.call('EXPIRE', KEYS[1], ARGV[2]) end
      return c
    LUA

    class << self
      # Record one event. Never raises.
      #
      # @param channel [String, Symbol] one of CHANNELS
      # @param stage [String, Symbol] one of STAGES
      # @param outcome [String, Symbol] one of STAGE_OUTCOMES[stage]
      # @param error [Exception, String, nil] source of error_class and the
      #   scrubbed error_message
      # @return [Hash, nil] the stored event (string keys), or nil when it
      #   could not be recorded
      def record(**fields)
        event = build(**fields)
        events.add(event, event['occurred_at'])
        trim!
        bump_count(event)
        event
      rescue StandardError => ex
        OT.le "[DeliveryEvent] event not recorded: #{ex.class}"
        nil
      end

      # Build the stored event without writing it. Raises ArgumentError on an
      # invalid channel/stage/outcome.
      #
      # @return [Hash] string-keyed event, nil fields omitted
      def build(channel:, stage:, outcome:, correlation_id: nil, message_id: nil,
                event_type: nil, template: nil, customer_id: nil, reason: nil,
                error: nil, http_status: nil, target_host: nil, provider: nil,
                provider_message_id: nil, duration_ms: nil, attempt_count: nil)
        channel = channel.to_s
        stage   = stage.to_s
        outcome = outcome.to_s
        raise ArgumentError, "invalid channel: #{channel}" unless CHANNELS.include?(channel)
        raise ArgumentError, "invalid stage: #{stage}" unless STAGES.include?(stage)
        unless STAGE_OUTCOMES.fetch(stage).include?(outcome)
          raise ArgumentError, "invalid outcome for stage #{stage}: #{outcome}"
        end

        webhook = channel == 'webhook'
        email   = channel == 'email'

        {
          'id' => Familia.generate_id,
          'occurred_at' => Familia.now.to_f,
          'channel' => channel,
          'stage' => stage,
          'outcome' => outcome,
          'correlation_id' => match(correlation_id, ID_PATTERN),
          'message_id' => match(message_id, ID_PATTERN),
          'event_type' => match(event_type, NAME_PATTERN),
          'template' => match(template, NAME_PATTERN),
          'customer_id' => match(customer_id, CUSTOMER_ID_PATTERN),
          'reason' => match(reason, REASON_PATTERN),
          'error_class' => error_class_of(error),
          'error_message' => error_message_of(error),
          'http_status' => webhook ? http_status_of(http_status) : nil,
          'target_host' => webhook ? match(target_host.to_s.downcase, HOST_PATTERN) : nil,
          'provider' => email ? match(provider.to_s.downcase, NAME_PATTERN) : nil,
          'provider_message_id' => email ? match(provider_message_id, PROVIDER_ID_PATTERN) : nil,
          'duration_ms' => non_negative(duration_ms),
          'attempt_count' => positive(attempt_count),
        }.compact
      end

      # Free text made safe to store: URIs, email addresses, provider
      # credential shapes and long opaque runs are replaced, whitespace is
      # collapsed, and the result is cut to MAX_MESSAGE_LENGTH.
      #
      # @param text [String, nil]
      # @return [String, nil] nil when nothing is left
      def scrub_message(text)
        return nil if text.nil?

        out = Onetime::Utils.utf8_safe(text.to_s)
        out = out.gsub(Onetime::Utils::Strings::EMBEDDED_URI_PATTERN, '[uri]')
        out = out.gsub(Onetime::Utils::Strings::EMAIL_PATTERN, '[email]')
        out = Onetime::Operations::Email::ErrorScrub.redact(out)
        out = out.gsub(OPAQUE_RUN_PATTERN, '[redacted]')
        out = out.gsub(/[[:cntrl:]\s]+/, ' ').strip
        out = out[0, MAX_MESSAGE_LENGTH]
        out.empty? ? nil : out
      end

      # Newest-first slice of the feed.
      # @return [Array<Hash>] events with string keys
      def recent(limit = 50, offset = 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset = 0 if offset.negative?
        events.revrange(offset, offset + limit - 1)
      end

      # @return [Integer] number of retained events
      def count
        events.element_count
      end

      # Enforce the count cap and the retention window.
      # @return [Integer] number of events removed
      def trim!(cap = MAX_EVENTS, max_age = RETENTION)
        cap     = cap.to_i
        max_age = max_age.to_i
        return 0 if cap.negative? || max_age.negative?

        removed  = events.remrangebyrank(0, -(cap + 1)).to_i
        removed += events.remrangebyscore('-inf', "(#{Familia.now.to_f - max_age}").to_i
        removed
      end

      # Per-day totals, oldest day first. Days with no events read as {}.
      #
      # @param days [Integer] how many UTC days back from today, inclusive
      # @return [Array<Hash>] [{ date: 'YYYYMMDD', counts: { 'email:delivery:sent' => 3 } }]
      def daily_counts(days = 7)
        days  = days.to_i.clamp(1, COUNTS_TTL / 86_400)
        today = Time.now.utc.to_date
        (0...days).map do |back|
          date = (today - (days - 1 - back)).strftime('%Y%m%d')
          raw  = Familia.dbclient.hgetall(counts_key(date))
          { date: date, counts: raw.transform_values(&:to_i) }
        end
      end

      def counts_key(date)
        "#{COUNTS_PREFIX}:#{date}"
      end

      private

      def bump_count(event)
        date  = Time.at(event['occurred_at']).utc.strftime('%Y%m%d')
        field = [event['channel'], event['stage'], event['outcome']].join(':')
        Familia.dbclient.eval(COUNT_LUA, keys: [counts_key(date)], argv: [field, COUNTS_TTL])
      rescue StandardError => ex
        # The event itself is stored; only the day total is missed.
        OT.le "[DeliveryEvent] count not recorded: #{ex.class}"
        nil
      end

      def match(value, pattern)
        return nil if value.nil?

        text = value.to_s
        pattern.match?(text) ? text : nil
      end

      def error_class_of(error)
        return nil unless error.is_a?(Exception)

        match(error.class.name, CLASS_PATTERN)
      end

      def error_message_of(error)
        return nil if error.nil?

        scrub_message(error.respond_to?(:message) ? error.message : error)
      end

      def http_status_of(value)
        status = Integer(value.to_s, 10, exception: false)
        status&.between?(100, 599) ? status : nil
      end

      def non_negative(value)
        return nil if value.nil?

        number = value.to_i
        number.negative? ? nil : number
      end

      def positive(value)
        return nil if value.nil?

        number = value.to_i
        number.positive? ? number : nil
      end
    end
  end
end
