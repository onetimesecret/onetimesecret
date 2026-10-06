# lib/onetime/log_scrubber.rb
#
# frozen_string_literal: true

require 'uri'
require 'semantic_logger'

module Onetime
  # Removes URI userinfo and URL query strings from every Semantic Logger
  # event before any appender sees it.
  #
  # Registered with SemanticLogger.on_log at the very start of Onetime.boot!
  # and again (idempotently) by the SetupLoggers initializer, before either
  # adds an appender. Semantic Logger calls on_log subscribers synchronously
  # in the logging thread, once per event, before the event is queued for
  # the appenders. One scrub therefore covers every appender: the console
  # appender and the optional ColonelAudit syslog appender alike, and every
  # log site that interpolates `ex.message`.
  #
  # Policy: Onetime::Utils.redact_uris_in_text, nothing else. Every URI loses
  # its userinfo and its whole query string, even a harmless `?page=2`.
  # Email addresses and identifiers stay readable.
  #
  # Fields scrubbed:
  #   message              A String, or a Hash/Array/Set walked like the
  #                        payload
  #   exception            The exception and its cause chain, as copies (see
  #                        Event#exception)
  #   tags, named_tags     Same walk as the payload
  #   payload              Walked through nested Hash, Array and Set values.
  #                        Strings are scrubbed; URI::Generic values and
  #                        Symbols that contain "://" become scrubbed Strings;
  #                        String, Symbol and URI Hash keys are scrubbed the
  #                        same way (see Event#insert for colliding keys);
  #                        Exception values become scrubbed copies.
  #
  # Not scrubbed:
  #   - any other object, as a payload value or as the message (Struct,
  #     Data, OpenStruct, models), which formatters render through #inspect
  #     or #to_s
  #   - the logger name, thread_name, metric, metric_amount, dimensions and
  #     context
  #   - backtraces: the call-site backtrace and those of the exception and
  #     its causes
  #   - on Semantic Logger 4.x, a logging block that returns a Hash can set
  #     name, thread_name or context through Log#assign_hash (5.x limits it
  #     to Log::ASSIGNABLE_KEYS); those stay unscrubbed. An exception set that
  #     way is scrubbed, since blocks run before the subscriber.
  #   - text an exception class renders from its own state in
  #     detailed_message, when neither its message chain nor (for a payload
  #     value) its inspect needs scrubbing: then no copy is made
  #   - an Exception payload value whose class defines to_json or as_json
  #     from its own state: the JSON formatter renders it through that
  #     method, which the copy does not override. (Exception#as_json from
  #     ActiveSupport or json/add reads #to_s or #message, which are
  #     scrubbed.)
  #
  # Nothing is mutated in place. Strings, hashes, arrays and exceptions
  # belong to the caller, who may still use, re-raise or report them. The
  # scrubber assigns new objects to the SemanticLogger::Log, which Semantic
  # Logger owns, and only when something changed. A copied exception shares
  # its backtrace Array with the original; the truncating formatter in
  # SetupLoggers (with_truncated_backtrace, under BACKTRACE_LINES) shortens
  # backtraces on a copy of its own and leaves that Array alone.
  #
  # Output that bypasses this scrub:
  #   - direct `warn`, `puts`, `$stdout` or `$stderr` writes
  #   - Semantic Logger's own internal logger (SemanticLogger::Processor.logger,
  #     used when an appender or a subscriber fails)
  #   - Sentry, which has its own scrubbing in SetupDiagnostics
  #   - later changes to logged objects. Values found clean stay shared with
  #     the caller by reference, and the async processor formats the event
  #     later on another thread; a caller that mutates a logged String or
  #     Hash after the log call can get the new, unscrubbed content
  #     formatted. That follows from scrubbing in on_log without copying
  #     clean values.
  #
  # Fail closed: a payload branch past a limit (depth, value count, cycle),
  # any string over MAX_STRING_BYTES, and any string whose original bytes would
  # overrun the event's MAX_EVENT_SCAN_BYTES are replaced by a fixed sentinel
  # string, never passed through. If the scrub itself raises, the event is
  # withheld (see .call).
  #
  # Defense in depth: call sites that already redact (e.g. HttpOrigin's
  # log_check_failure) keep doing so.
  module LogScrubber
    # A string without it holds no URI the policy would change. The byte caps
    # are reserved before searching for it (see Event#string).
    URI_MARKER = '://'

    # ANSI escape sequences, matched the way SemanticLogger::Log
    # #cleansed_message removes them before the JSON, Raw and Loki
    # formatters print a message (4.18: /(\e(\[([\d;]*[mz]?))?)?/,
    # 5.1: /\e\[[\d;]*[mz]?|\e/): SGR sequences ("\e[0m"), "\e[...z" and a
    # bare ESC. Only those are removed before probing. Other splits a
    # terminal hides (non-SGR CSI such as "\e[K", OSC, zero-width
    # characters, backspace) are not joined, so a URI split by one is not
    # recognized. The URIs this scrub is for come from connection errors in
    # exception messages, not from text built to evade it.
    ANSI_ESCAPE = /\e(?:\[[\d;]*[mz]?)?/

    # The redaction regex (Utils::Strings::EMBEDDED_URI_PATTERN) runs in
    # linear time only because of Onigmo's match cache; a spec pins that.
    # On top of it, these caps bound the scrub work per event: everything
    # done on the logging thread, and everything the Semantic Logger
    # formatters call when they render the event. Every String and Symbol name
    # is charged at its original size before any content or encoding probe,
    # transcoding or ANSI removal, so those steps cannot shrink their way
    # around either byte cap. A payload
    # exception's own inspect and to_s are scrubbed up front and memoized. Not
    # covered: exception copies' detailed_message and full_message, and the
    # inspect of the logged exception's copies and of cause copies, which scrub themselves
    # when called, under MAX_STRING_BYTES per call. No Semantic Logger
    # formatter calls them.
    MAX_STRING_BYTES     = 16 * 1024 # every visited string (~1.6 ms worst case)
    MAX_EVENT_SCAN_BYTES = 64 * 1024 # all visited string bytes in one event
    MAX_NODES            = 1_000     # values and exception links in one event, all fields
    MAX_DEPTH            = 8         # container nesting within one field
    MAX_EXCEPTION_CHAIN  = 5         # = SemanticLogger::Log::MAX_EXCEPTIONS_TO_UNWRAP

    DEPTH_SENTINEL         = '[log scrub: nested too deep]'
    CYCLE_SENTINEL         = '[log scrub: circular reference]'
    NODES_SENTINEL         = '[log scrub: too many values]'
    OVERSIZED_SENTINEL     = '[log scrub: oversized string]'
    UNREADABLE_SENTINEL    = '[log scrub: unreadable encoding with ":"]'
    BUDGET_SENTINEL        = '[log scrub: event scan budget spent]'
    SET_COLLISION_SENTINEL = '[log scrub: colliding set member]'
    FAILURE_MESSAGE        = '[log scrub failed: event withheld]'

    # Key added to a Hash that the node limit cut short. An Array or Set
    # gets NODES_SENTINEL added instead.
    TRUNCATED_KEY = :log_scrub_truncated

    class << self
      # Register as a Semantic Logger on_log subscriber. Idempotent: boot!,
      # the initializer and specs may all run this, and on_log appends to a
      # list. Always this module object, never a block, so the identity
      # check finds it.
      #
      # @return [Boolean] true when this call registered the scrubber
      def register!
        return false if registered?

        SemanticLogger.on_log(self)
        true
      end

      # Nil-safe: Semantic Logger creates the subscriber list on the first
      # on_log call.
      def registered?
        subscribers = SemanticLogger::Logger.subscribers
        !subscribers.nil? && subscribers.any? { |subscriber| subscriber.equal?(self) }
      end

      # The on_log hook. Never raises.
      #
      # Semantic Logger wraps each subscriber in `rescue Exception`, writes
      # the error to $stderr through its internal logger, and then queues the
      # event anyway, possibly half scrubbed. So every failure is caught
      # here, the event is withheld (see #withhold), and nothing is
      # re-raised: a re-raise would only add an unscrubbed line from that
      # internal logger.
      #
      # @param log [SemanticLogger::Log]
      # @return [nil]
      def call(log)
        scrub_event(log)
        nil
      rescue Exception => ex
        withhold(log, ex)
        nil
      end

      # Scrub one string outside an event (per-string cap only).
      #
      # @param str [String]
      # @return [String] str itself when nothing changes, else a new String
      def scrub_string(str)
        Event.new.string(str)
      end

      # The text to probe and redact: str itself when it is valid UTF-8 or
      # plain ASCII, otherwise a valid UTF-8 copy, and without ANSI escapes.
      #
      # Both steps put back together a "://" that the raw bytes split.
      # A stray invalid byte ("redis:\xFF//u:pw@h") leaves the credential
      # readable in the output but hides the marker from a byte-level probe;
      # dropping it, as redact_uris_in_text's utf8_safe does, lets the
      # redactor recognize the URI. An escape ("redis:\e[0m//u:pw@h") is
      # removed by Log#cleansed_message and by a terminal, which print the
      # joined URI. ASCII-incompatible encodings (UTF-16/32) are transcoded
      # first, since probing them with an ASCII marker raises.
      #
      # After its bytes are reserved, text in an ASCII-compatible encoding
      # with no ":" byte is rejected: neither dropping bytes nor removing
      # escapes can create one. That keeps candidate probing for the common
      # case (a plain message, Symbol payload keys) to a single byte search.
      #
      # Valid UTF-8 and plain ASCII need work only when their raw bytes hold a
      # URI marker or ANSI that could split one. Other encodings may reveal a
      # marker during conversion, so a colon makes them candidates. Event
      # callers must reserve the input's byte budget before calling this;
      # #scan_text applies its standalone per-string cap first.
      def scan_candidate?(str)
        return false if str.encoding.ascii_compatible? && !str.include?(':')
        return true unless (str.encoding == Encoding::UTF_8 && str.valid_encoding?) || str.ascii_only?

        str.include?(URI_MARKER) || str.include?("\e")
      end

      # @param candidate [Boolean] whether #scan_candidate? already passed
      # @return [String, nil] nil when the text holds no URI_MARKER;
      #   a sentinel for oversized or unreadable text
      def scan_text(str, candidate: false)
        return OVERSIZED_SENTINEL if str.bytesize > MAX_STRING_BYTES
        return unless candidate || scan_candidate?(str)

        text = if (str.encoding == Encoding::UTF_8 && str.valid_encoding?) || str.ascii_only?
                 str
               else
                 utf8_copy(str)
               end
        return text if text.nil? || text.equal?(UNREADABLE_SENTINEL)

        text = text.gsub(ANSI_ESCAPE, '') if text.include?("\e")
        text.include?(URI_MARKER) ? text : nil
      end

      private

      # The message and exception go first, so the event's byte budget favors
      # them over tags and payload. A non-nil message always creates the event
      # state because its bytes must be reserved before probing its content.
      def scrub_event(log)
        event          = scrub_message(log)
        log.exception  = (event ||= Event.new).exception(log.exception) if log.exception.is_a?(Exception)
        log.tags       = (event ||= Event.new).walk(log.tags) if present?(log.tags)
        log.named_tags = (event ||= Event.new).walk(log.named_tags) if present?(log.named_tags)
        log.payload    = (event || Event.new).walk(log.payload) if present?(log.payload)
      end

      # @return [Event, nil] the event state, when the message needed one
      def scrub_message(log)
        message = log.message
        return if message.nil?

        event = Event.new
        if message.is_a?(String)
          scrubbed    = event.string(message)
          log.message = scrubbed unless scrubbed.equal?(message)
        else
          log.message = event.walk(message)
        end
        event
      end

      def present?(value)
        !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
      end

      # Valid text in another encoding is transcoded (Windows-1252 "café"
      # stays "café"); only binary and invalid UTF-8 are read as UTF-8 with
      # the invalid bytes dropped. Invalid bytes in other encodings are
      # dropped by the transcoder.
      def utf8_copy(str)
        case str.encoding
        when Encoding::UTF_8, Encoding::BINARY then Onetime::Utils.utf8_safe(str)
        else str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
        end
      rescue EncodingError
        # No converter (dummy encodings: UTF-7, ISO-2022-JP-2), so the text
        # cannot be read reliably; UTF-7 can even spell "://" in base64. A
        # string whose bytes hold a ":" is replaced by UNREADABLE_SENTINEL
        # (fail closed, this string only); any other is left as it is.
        str.b.include?(':') ? UNREADABLE_SENTINEL : nil
      end

      # Withholding keeps level, logger name, time, duration, thread_name,
      # the call-site backtrace, metric, metric_amount, dimensions and
      # context. None of those is ever scrubbed, so withholding does not
      # widen what they show.
      def withhold(log, error)
        log.message    = FAILURE_MESSAGE
        log.payload    = { log_scrub_error: error.class.name.to_s }
        log.exception  = nil
        log.tags       = []
        log.named_tags = {}
      rescue Exception
        nil
      end
    end

    # The limits of one event: a string-byte budget and a value budget shared
    # by all its fields. #walk returns its argument itself when
    # nothing in it changed; otherwise a new plain Hash, Array or Set
    # holding the changed values.
    class Event
      def initialize
        @nodes     = 0
        @scanned   = 0
        @ancestors = nil
        @suffixes  = nil
      end

      def string(str, unchanged: str)
        original_bytes = str.bytesize
        return OVERSIZED_SENTINEL if original_bytes > MAX_STRING_BYTES
        return BUDGET_SENTINEL if @scanned + original_bytes > MAX_EVENT_SCAN_BYTES

        @scanned += original_bytes
        return unchanged unless LogScrubber.scan_candidate?(str)

        text = LogScrubber.scan_text(str, candidate: true)
        return unchanged unless text
        return text if text.equal?(UNREADABLE_SENTINEL) || text.equal?(OVERSIZED_SENTINEL)
        return OVERSIZED_SENTINEL if text.bytesize > MAX_STRING_BYTES

        extra_bytes = text.bytesize - original_bytes
        if extra_bytes.positive?
          return BUDGET_SENTINEL if @scanned + extra_bytes > MAX_EVENT_SCAN_BYTES

          @scanned += extra_bytes
        end

        scrubbed = Onetime::Utils.redact_uris_in_text(text)
        scrubbed == str ? str : scrubbed
      end

      def walk(value, depth = 0)
        @nodes += 1
        case value
        when String then string(value)
        when Symbol then symbol(value)
        when Hash then enter(value, depth) { scrub_hash(value, depth) }
        when Array then enter(value, depth) { scrub_array(value, depth) }
        when URI::Generic then string(value.to_s)
        when Set then enter(value, depth) { scrub_set(value, depth) }
        when Exception then payload_exception(value)
        else value
        end
      end

      # The logged exception: itself when no message in its chain changes;
      # otherwise a copy chain. Each link is a `dup` of the original (same
      # class, same backtrace) whose message, to_s and cause answer with
      # scrubbed values, and whose inspect, detailed_message and
      # full_message are scrubbed on the way out. The originals and their
      # causes are untouched, so a re-raise or a Sentry report still sees
      # the real exception. dup also drops the frozen state, which is what
      # lets a frozen exception be copied.
      #
      # The chain is followed the way Semantic Logger follows it (cause,
      # then continued_exception, then original_exception) and stops at a
      # repeat. Every link counts toward MAX_NODES. The chain is cut, with
      # the last copy's cause nil, past MAX_EXCEPTION_CHAIN links, when the
      # node budget runs out, and at the first link the scan budget cannot
      # cover (that link keeps BUDGET_SENTINEL as its message). A cut chain
      # always takes the copy path.
      #
      # @param exception [Exception]
      # @return [Exception]
      def exception(exception)
        links, texts, changed = scan_chain(exception)
        changed ? copy_chain(links, texts) : exception
      end

      private

      def scrub_key(key)
        case key
        when Symbol then symbol(key)
        when String then string(key)
        when URI::Generic then string(key.to_s)
        else key
        end
      end

      # Symbol names take the same bounded path as Strings. An unchanged name
      # keeps its Symbol type; a name containing a URI becomes a String.
      def symbol(sym)
        string(sym.name, unchanged: sym)
      end

      # An Exception inside a payload is rendered through #inspect (text
      # formatters) or #to_s (JSON, Logfmt). Both are scrubbed here, on the
      # caller's thread and charged to the event's budget (#to_s only when
      # the class makes it differ from #message, which the chain scan
      # already covered), and a copy returns those memos, so rendering the
      # payload does no scrub work. The value becomes the sentinel String
      # rather than a copy when the budget cannot cover the head link's
      # message, its inspect or its to_s. A later link the budget cannot
      # cover still yields a copy: that link's message is the placeholder
      # and the chain ends there (#scan_chain).
      def payload_exception(exception)
        links, texts, changed = scan_chain(exception)
        return texts.first if [BUDGET_SENTINEL, NODES_SENTINEL].any? { |s| texts.first.equal?(s) }

        renders = { inspect: exception.inspect, to_s: distinct_to_s(exception) }.compact
        shown   = renders.transform_values { |text| string(text) }
        return BUDGET_SENTINEL if shown.any? { |_, text| text.equal?(BUDGET_SENTINEL) }
        return exception unless changed || shown.any? { |name, text| !text.equal?(renders[name]) }

        copy_chain(links, texts, shown)
      end

      # #to_s when the class makes it differ from #message, else nil.
      def distinct_to_s(exception)
        text = exception.to_s
        text = text.to_s unless text.is_a?(String)
        text == exception_message(exception) ? nil : text
      end

      # @return [Array(Array<Exception>, Array<String>, Boolean)] the links
      #   kept, their scrubbed messages, and whether a copy is needed
      def scan_chain(exception)
        links   = []
        texts   = []
        changed = false
        link    = exception
        while link && links.none? { |seen| seen.equal?(link) }
          if links.size >= MAX_EXCEPTION_CHAIN || @nodes >= MAX_NODES
            changed = cut_chain(links, texts, link)
            break
          end
          changed = true if scan_link(link, links, texts)
          break if texts.last.equal?(BUDGET_SENTINEL)

          link = next_exception(link)
        end
        [links, texts, changed]
      end

      # @return [Boolean] whether the link's message changed
      def scan_link(link, links, texts)
        @nodes += 1
        message = exception_message(link)
        text    = string(message)
        links << link
        texts << text
        !text.equal?(message)
      end

      # A chain cut at its head keeps the head, with NODES_SENTINEL as its
      # message, so the logged exception is still an exception.
      def cut_chain(links, texts, link)
        if links.empty?
          links << link
          texts << NODES_SENTINEL
        end
        true
      end

      # Mirrors SemanticLogger::Log#each_exception.
      def next_exception(exception)
        if exception.cause
          exception.cause
        elsif exception.respond_to?(:continued_exception) && exception.continued_exception
          exception.continued_exception
        elsif exception.respond_to?(:original_exception)
          exception.original_exception
        end
      end

      # Classes may override #message (redis-client appends its server URL
      # there), so read it rather than the constructor argument.
      def exception_message(exception)
        message = exception.message
        message.is_a?(String) ? message : message.to_s
      end

      # @param head_renders [Hash{Symbol => String}] the head's inspect and
      #   (when it differs from message) to_s, scrubbed and charged to the
      #   budget (payload values); an absent inspect is scrubbed lazily, an
      #   absent to_s answers with the scrubbed message
      def copy_chain(links, texts, head_renders = {})
        (links.size - 1).downto(0).inject(nil) do |cause, i|
          sanitized_copy(links[i], texts[i], cause, i.zero? ? head_renders : {})
        end
      end

      def sanitized_copy(original, message, cause, renders)
        copy = original.dup
        raise TypeError, "#{original.class}#dup returned the original" if copy.equal?(original)

        to_s_text    = renders.fetch(:to_s, message)
        inspect_text = renders[:inspect]
        copy.define_singleton_method(:message) { message }
        copy.define_singleton_method(:to_s) { to_s_text }
        copy.define_singleton_method(:cause) { cause }
        # The copy's cause already stands in for whichever link came next.
        copy.define_singleton_method(:continued_exception) { nil } if copy.respond_to?(:continued_exception)
        copy.define_singleton_method(:original_exception) { nil } if copy.respond_to?(:original_exception)
        if inspect_text
          copy.define_singleton_method(:inspect) { inspect_text }
        else
          scrub_lazily(copy, :inspect, message)
        end
        [:detailed_message, :full_message].each { |renderer| scrub_lazily(copy, renderer, message) }
        copy
      end

      # Semantic Logger's formatters take the text of each link from
      # #message and walk the chain through #cause, both answered from the
      # scrub above. Other renderers go further: a class's inspect may show
      # its own state (Faraday::Error shows the response, request URL
      # included), full_message reads the cause from an internal slot that
      # dup copied and #cause cannot redirect, and detailed_message may
      # append text. These are scrubbed when called, under the per-string
      # cap only, and fall back to the scrubbed message. No Semantic Logger
      # formatter calls them on the logged exception; a payload value's
      # inspect and to_s are memoized at scrub time instead
      # (#payload_exception).
      def scrub_lazily(copy, renderer, message)
        copy.define_singleton_method(renderer) do |**opts|
          LogScrubber.scrub_string(super(**opts))
        rescue StandardError
          message
        end
      end

      # Depth and cycle limits replace the whole container. The ancestor
      # list holds only the current path (at most MAX_DEPTH entries), so a
      # value shared by two siblings is walked twice rather than mistaken
      # for a cycle.
      def enter(container, depth)
        return container if container.empty?
        return DEPTH_SENTINEL if depth >= MAX_DEPTH

        ancestors = (@ancestors ||= [])
        return CYCLE_SENTINEL if ancestors.any? { |ancestor| ancestor.equal?(container) }

        ancestors.push(container)
        begin
          yield
        ensure
          ancestors.pop
        end
      end

      # The node limit keeps what was already walked and replaces the rest
      # with one marker, so the work stays bounded however large the
      # container is.
      def scrub_hash(hash, depth)
        result = nil
        index  = 0
        hash.each_pair do |key, value|
          if @nodes >= MAX_NODES
            result = insert(result || hash.first(index).to_h, TRUNCATED_KEY, NODES_SENTINEL)
            break
          end

          new_key   = scrub_key(key)
          new_value = walk(value, depth + 1)
          result  ||= hash.first(index).to_h unless new_key.equal?(key) && new_value.equal?(value)
          insert(result, new_key, new_value) if result
          index    += 1
        end
        result || hash
      end

      # Scrubbing can make two keys equal: "redis://a:x@h" and
      # "redis://a:y@h" both become "redis://***@h". The key inserted later
      # gets the lowest free " (2)", " (3)", ... suffix, so no value is
      # dropped and the outcome depends only on the Hash's order. A key the
      # caller already wrote with a suffix is a key like any other: if it
      # collides too, it gets its own suffix ("x (2) (2)").
      def insert(hash, key, value)
        hash[hash.key?(key) ? distinct_key(hash, key) : key] = value
        hash
      end

      # A per-Hash counter remembers the next suffix to try for each key, so
      # n collisions cost O(n) in total instead of rescanning from " (2)".
      # Keys are only ever added, so every suffix below the counter is taken.
      def distinct_key(hash, key)
        counters      = ((@suffixes ||= {}.compare_by_identity)[hash] ||= {})
        suffix        = counters.fetch(key, 2)
        suffix       += 1 while hash.key?("#{key} (#{suffix})")
        counters[key] = suffix + 1
        "#{key} (#{suffix})"
      end

      # Set equality can collapse distinct caller values after scrubbing. Keep
      # scrubbed Strings useful by suffixing them like colliding Hash keys; for
      # other values, insert an explicit safe marker. Numbering also preserves
      # cardinality across three or more collisions and caller-written markers.
      def insert_member(set, member)
        return set << member unless set.include?(member)

        base     = member.is_a?(String) ? member : SET_COLLISION_SENTINEL
        distinct = set.include?(base) ? distinct_member(set, base) : base
        set << distinct
      end

      def distinct_member(set, member)
        counters         = ((@suffixes ||= {}.compare_by_identity)[set] ||= {})
        suffix           = counters.fetch(member, 2)
        suffix          += 1 while set.include?("#{member} (#{suffix})")
        counters[member] = suffix + 1
        "#{member} (#{suffix})"
      end

      def scrub_array(array, depth)
        result = nil
        array.each_with_index do |value, index|
          if @nodes >= MAX_NODES
            (result ||= array.first(index)) << NODES_SENTINEL
            break
          end

          new_value = walk(value, depth + 1)
          result  ||= array.first(index) unless new_value.equal?(value)
          result << new_value if result
        end
        result || array
      end

      def scrub_set(set, depth)
        result = nil
        index  = 0
        set.each do |member|
          if @nodes >= MAX_NODES
            result ||= Set.new(set.first(index))
            insert_member(result, NODES_SENTINEL)
            break
          end

          new_member = walk(member, depth + 1)
          result   ||= Set.new(set.first(index)) unless new_member.equal?(member)
          insert_member(result, new_member) if result
          index     += 1
        end
        result || set
      end
    end
    private_constant :Event
  end
end
