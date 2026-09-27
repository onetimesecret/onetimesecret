# spec/unit/onetime/log_scrubber_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'uri'
require 'onetime/log_scrubber'

RSpec.describe Onetime::LogScrubber do
  let(:secret) { 's3cret' }
  let(:dirty_uri) { "redis://user:#{secret}@db:6379/0?password=#{secret}" }
  let(:clean_uri) { 'redis://***@db:6379/0?***' }

  def build_log(message: nil, payload: nil, exception: nil, tags: [], named_tags: {})
    SemanticLogger::Log.new('LogScrubberSpec', :error).tap do |log|
      log.message    = message
      log.payload    = payload
      log.exception  = exception
      log.tags       = tags
      log.named_tags = named_tags
    end
  end

  def scrubbed(**fields)
    build_log(**fields).tap { |log| described_class.call(log) }
  end

  def withheld?(log)
    log.message == described_class::FAILURE_MESSAGE || (log.payload.is_a?(Hash) && log.payload.key?(:log_scrub_error))
  end

  # Identity, frozen state, content, encoding, singleton methods and ivars of
  # everything reachable, to prove the caller's objects come back unchanged.
  def snapshot(value, seen = {}.compare_by_identity)
    return [:seen, value.object_id] if seen.key?(value)

    seen[value] = true
    head = [value.object_id, value.frozen?, value.singleton_methods.sort]
    case value
    when Hash then head + value.map { |k, v| [snapshot(k, seen), snapshot(v, seen)] }
    when Array, Set then head + value.map { |v| snapshot(v, seen) }
    when String then head + [value.encoding.name, value.b]
    when Exception
      head + [value.message, value.cause&.object_id, value.instance_variables.map { |i| [i, snapshot(value.instance_variable_get(i), seen)] }]
    else head + [value.inspect]
    end
  end

  def deep_freeze(value)
    case value
    when Hash then value.each_pair { |k, v| deep_freeze(k) && deep_freeze(v) }
    when Array then value.each { |v| deep_freeze(v) }
    end
    value.freeze
  end

  # raise/rescue so the exception carries a real backtrace and a real cause.
  def raised(klass, message, *args, cause: nil)
    if cause
      begin
        raise cause
      rescue StandardError
        raise klass.new(message, *args)
      end
    end
    raise klass.new(message, *args)
  rescue klass => ex
    ex
  end

  # redis-client shape: the server URL is appended in #message, not passed
  # to the constructor. A URI followed by ")" keeps the ")" inside its span,
  # so the query mask swallows it (redact_uris_in_text's documented policy).
  let(:message_override_class) do
    stub_const('LogScrubberSpec::ConnectionError', Class.new(StandardError) do
      def initialize(message, url)
        super(message)
        @url = url
      end

      def message = "#{super} (#{@url})"
    end
    )
  end

  describe '.call on the message' do
    it 'removes userinfo and the query string' do
      log = scrubbed(message: "connect failed: #{dirty_uri} (retrying)")

      expect(log.message).to eq("connect failed: #{clean_uri} (retrying)")
    end

    it 'removes even a harmless query string' do
      expect(scrubbed(message: 'GET https://example.com/list?page=2 done').message)
        .to eq('GET https://example.com/list?*** done')
    end

    it 'keeps email addresses and prose' do
      expect(scrubbed(message: "alice@example.com failed at https://h.example/x?token=#{secret}").message)
        .to eq('alice@example.com failed at https://h.example/x?***')
    end

    it 'returns a message without "://" as the same object' do
      message = +'no uri here, user:pass@host?x=1'
      expect(scrubbed(message: message).message).to equal(message)
    end

    it 'returns a message whose URIs need no change as the same object' do
      message = +'fetched https://example.com/path/to/thing'
      expect(scrubbed(message: message).message).to equal(message)
    end

    it 'does not mutate a frozen caller string' do
      message = "boom #{dirty_uri}".freeze

      log = scrubbed(message: message)

      expect(log.message).to eq("boom #{clean_uri}")
      expect(message).to include(secret)
    end

    it 'does not mutate an unfrozen caller string' do
      message = +"boom #{dirty_uri}"
      before  = snapshot(message)

      log = scrubbed(message: message)

      expect(log.message).to eq("boom #{clean_uri}")
      expect(snapshot(message)).to eq(before)
    end

    # Log#cleansed_message (JSON, Raw, Loki) and a terminal drop the escape
    # and show the joined URI, so the probe must see it joined as well.
    it 'scrubs a URI whose "://" is split by an ANSI escape' do
      ["connect redis:\e[0m//default:#{secret}@cache:6379/0", "connect redis:\e//default:#{secret}@cache:6379/0"].each do |message|
        expect(scrubbed(message: message).message).to eq('connect redis://***@cache:6379/0')
      end
    end

    it 'keeps ANSI escapes in a message without a URI' do
      message = +"\e[31mred\e[0m text"
      expect(scrubbed(message: message).message).to equal(message)
    end
  end

  describe '.call on the payload' do
    it 'scrubs strings in nested hashes and arrays' do
      payload = { outer: { list: ['plain', dirty_uri, { deep: "x #{dirty_uri}" }] }, count: 3 }

      expect(scrubbed(payload: payload).payload)
        .to eq(outer: { list: ['plain', clean_uri, { deep: "x #{clean_uri}" }] }, count: 3)
    end

    it 'scrubs an `error: ex.message` field' do
      ex  = raised(message_override_class, 'refused', dirty_uri)
      log = scrubbed(message: 'check failed', payload: { error: ex.message })

      expect(log.payload[:error]).to eq("refused (#{clean_uri}")
    end

    it 'turns a URI::Generic value into a scrubbed string' do
      uri = URI("https://user:#{secret}@api.example.com:8443/x?token=#{secret}")
      log = scrubbed(payload: { uri: uri, safe: URI('https://example.com/x') })

      expect(log.payload).to eq(uri: 'https://***@api.example.com:8443/x?***', safe: 'https://example.com/x')
    end

    it 'scrubs string hash keys' do
      expect(scrubbed(payload: { dirty_uri => 1 }).payload).to eq(clean_uri => 1)
    end

    it 'scrubs Symbol and URI hash keys into String keys' do
      uri = URI("https://u:#{secret}@h.example/x?t=#{secret}")
      log = scrubbed(payload: { :"#{dirty_uri}" => 1, uri => 2, plain: 3 }, named_tags: { :"#{dirty_uri}" => 4 })

      expect(log.payload).to eq(clean_uri => 1, 'https://***@h.example/x?***' => 2, plain: 3)
      expect(log.named_tags).to eq(clean_uri => 4)
    end

    # Two keys that scrub to the same text both survive: the later one in
    # the Hash's order gets a numbered suffix.
    it 'keeps both values when scrubbed keys collide' do
      other = dirty_uri.sub(secret, 'other')
      log   = scrubbed(payload: { dirty_uri => 1, other => 2, clean_uri => 3 })

      expect(log.payload).to eq(clean_uri => 1, "#{clean_uri} (2)" => 2, "#{clean_uri} (3)" => 3)
    end

    # A caller's own suffixed key is a key like any other: it keeps its
    # place, the next collision skips past it, and if it collides itself it
    # gets its own suffix.
    it 'gives each colliding key the lowest free suffix, past caller-written ones' do
      log = scrubbed(payload: { 'redis://a:1@h' => 1, 'redis://b:2@h' => 2, 'redis://***@h (2)' => 3, 'redis://***@h' => 4 })

      expect(log.payload).to eq('redis://***@h' => 1, 'redis://***@h (2)' => 2, 'redis://***@h (2) (2)' => 3, 'redis://***@h (3)' => 4)
    end

    it 'keeps every value when many keys collide' do
      payload = Array.new(300) { |i| ["redis://u:#{i}@h", i] }.to_h

      result = scrubbed(payload: payload).payload

      expect(result.values).to eq((0...300).to_a)
      expect(result.keys.last).to eq('redis://***@h (300)')
    end

    it 'walks a Set, building a new one only when a member changes' do
      clean = Set['a', 'https://example.com/ok']
      log   = scrubbed(payload: { urls: Set['a', dirty_uri], clean: clean })

      expect(log.payload[:urls]).to eq(Set['a', clean_uri])
      expect(log.payload[:clean]).to equal(clean)
    end

    it 'keeps every member when several Set strings scrub to the same value' do
      urls   = Set.new(Array.new(4) { |i| +"redis://user:#{secret}#{i}@db:6379/0?password=#{secret}#{i}" })
      before = snapshot(urls)

      result = scrubbed(payload: { urls: urls }).payload[:urls]

      expect(result).to eq(Set.new([clean_uri, *2.upto(4).map { |i| "#{clean_uri} (#{i})" }]))
      expect(result.size).to eq(urls.size)
      expect(result.inspect).not_to include(secret)
      expect(snapshot(urls)).to eq(before)
    end

    it 'marks a collision between scrubbed non-String Set members' do
      other  = dirty_uri.sub(secret, 'other')
      lists  = Set[[dirty_uri], [other]]
      before = snapshot(lists)

      result = scrubbed(payload: { lists: lists }).payload[:lists]

      expect(result).to eq(Set[[clean_uri], described_class::SET_COLLISION_SENTINEL])
      expect(result.size).to eq(lists.size)
      expect(result.inspect).not_to include(secret)
      expect(snapshot(lists)).to eq(before)
    end

    it 'never mutates a deep-frozen caller payload' do
      payload  = deep_freeze({ a: [dirty_uri, { b: dirty_uri }], c: 'ok' })
      snapshot = Marshal.load(Marshal.dump(payload))

      log = scrubbed(payload: payload)

      expect(withheld?(log)).to be(false)
      expect(log.payload).to eq(a: [clean_uri, { b: clean_uri }], c: 'ok')
      expect(payload).to eq(snapshot)
    end

    # Frozen inputs alone cannot prove this: a mutating scrubber would raise
    # FrozenError, withhold the event, and the frozen input would still
    # compare equal.
    it 'leaves unfrozen caller objects unchanged while scrubbing the event' do
      inner   = raised(ArgumentError, "inner #{dirty_uri}")
      outer   = raised(RuntimeError, "outer #{dirty_uri}", cause: inner)
      outer.extend(Module.new { def extra = :x })
      outer.instance_variable_set(:@ctx, { url: +dirty_uri })
      payload = { a: +"x #{dirty_uri}", b: [+dirty_uri, { c: (+"c #{dirty_uri}").b }], d: "wide #{dirty_uri}".encode('UTF-16LE'),
                  e: URI("https://u:#{secret}@h.example/x?q=1"), f: :"#{dirty_uri}", g: outer, +dirty_uri => 1, h: Set[+dirty_uri] }
      payload[:self] = payload
      fields  = { message: +"m #{dirty_uri}", payload: payload, exception: outer, tags: [+dirty_uri], named_tags: { up: +dirty_uri } }
      before  = snapshot(fields)

      log = scrubbed(**fields)

      expect(withheld?(log)).to be(false)
      expect([log.message, log.payload, log.tags, log.named_tags, log.exception.message].inspect).not_to include(secret)
      expect(snapshot(fields)).to eq(before)
    end

    it 'returns an unchanged payload as the same object and shares unchanged branches' do
      clean  = { list: %w[a b], nested: { k: 'https://example.com/ok' } }
      mixed  = { clean: clean, dirty: dirty_uri }

      expect(scrubbed(payload: clean).payload).to equal(clean)
      expect(scrubbed(payload: mixed).payload[:clean]).to equal(clean)
    end

    it 'turns a Symbol that contains "://" into a scrubbed string and keeps any other Symbol' do
      log = scrubbed(payload: { url: :"#{dirty_uri}", plain: :"https://example.com/ok", name: :ok })

      expect(log.payload).to eq(url: clean_uri, plain: 'https://example.com/ok', name: :ok)
    end

    it 'replaces an Exception value with a scrubbed copy' do
      ex  = raised(message_override_class, 'refused', dirty_uri)
      log = scrubbed(payload: { error: ex })

      expect(log.payload[:error]).to be_a(message_override_class)
      expect(log.payload[:error].message).to eq("refused (#{clean_uri}")
      expect(log.payload[:error].inspect).not_to include(secret)
      expect(ex.message).to include(secret)
    end

    # Faraday::Error shape: a clean message, but #inspect renders the
    # response, request URL included. Text formatters show payload values
    # through #inspect.
    it 'copies an Exception value whose inspect shows a URI even when its message is clean' do
      klass = Class.new(StandardError) do
        def initialize(message, response) = (super(message); @response = response)
        def inspect = "#<#{self.class} response=#{@response.inspect}>"
      end
      ex    = klass.new('HTTP 400', { url: dirty_uri })

      value = scrubbed(payload: { error: ex }).payload[:error]

      expect(value).not_to equal(ex)
      expect(value.inspect).to include(clean_uri)
      expect(value.inspect).not_to include(secret)
      expect(ex.inspect).to include(secret)
    end

    # JSON and Logfmt render a payload exception through #to_s. A class can
    # keep #message and #inspect clean while its #to_s shows a URL.
    it 'scrubs a payload exception whose to_s differs from its message' do
      klass = Class.new(StandardError) do
        def initialize(url) = (super('fail'); @url = url)
        def message = 'fail'
        def to_s = "fail #{@url}"
        def inspect = '#<T>'
      end
      ex    = klass.new(dirty_uri)

      value = scrubbed(payload: { err: ex }).payload[:err]

      expect(value).not_to equal(ex)
      expect([value.to_s, value.message, value.inspect]).to eq(["fail #{clean_uri}", 'fail', '#<T>'])
      expect({ err: value }.to_json).not_to include(secret)
      expect(ex.to_s).to include(secret)
    end

    # Rendering the payload must not run the redactor again, outside the
    # event's budget: the copy answers inspect from a memo made at scrub
    # time.
    it 'memoizes the scrubbed inspect of a payload exception copy' do
      ex = raised(RuntimeError, "down #{dirty_uri}")

      value = scrubbed(payload: { error: ex }).payload[:error]
      allow(Onetime::Utils).to receive(:redact_uris_in_text).and_call_original
      rendered = value.inspect

      # The ">" after the URI falls inside the masked query span.
      expect(rendered).to eq("#<RuntimeError: down #{clean_uri}")
      expect(value.inspect).to equal(rendered)
      expect(Onetime::Utils).not_to have_received(:redact_uris_in_text)
    end

    it 'turns a payload exception whose inspect overruns the budget into the budget sentinel' do
      klass  = Class.new(StandardError) { def inspect = "#<K #{'a' * 10_000} #{@url}>" }
      errors = Array.new(8) { klass.new("down #{dirty_uri}").tap { |e| e.instance_variable_set(:@url, dirty_uri) } }

      result = scrubbed(payload: { errors: errors }).payload[:errors]

      expect(result.first).to be_a(klass)
      expect(result.last).to eq(described_class::BUDGET_SENTINEL)
      expect(result.map(&:inspect).join).not_to include(secret)
    end

    # Documented limit: other object types are not walked.
    it 'passes other object types through untouched' do
      struct = Struct.new(:url).new(dirty_uri)

      expect(scrubbed(payload: { obj: struct, sym: :x, num: 1 }).payload[:obj]).to equal(struct)
    end
  end

  describe '.call on tags' do
    it 'scrubs tags and named tags' do
      log = scrubbed(tags: ['req', dirty_uri], named_tags: { upstream: dirty_uri, id: 'abc' })

      expect(log.tags).to eq(['req', clean_uri])
      expect(log.named_tags).to eq(upstream: clean_uri, id: 'abc')
    end
  end

  describe '.call on the exception' do
    let(:inner) { raised(ArgumentError, "bad option in #{dirty_uri}") }
    let(:outer) { raised(message_override_class, 'connect failed', dirty_uri, cause: inner) }

    it 'replaces the exception with a scrubbed copy chain' do
      copy = scrubbed(exception: outer).exception

      expect(copy).not_to equal(outer)
      expect(copy.message).to eq("connect failed (#{clean_uri}")
      expect(copy.cause).not_to equal(inner)
      expect(copy.cause.message).to eq("bad option in #{clean_uri}")
    end

    it 'keeps each class name and backtrace' do
      copy = scrubbed(exception: outer).exception

      expect(copy.class.name).to eq('LogScrubberSpec::ConnectionError')
      expect(copy.backtrace).to eq(outer.backtrace).and(be_an(Array))
      expect(copy.cause.class).to eq(ArgumentError)
      expect(copy.cause.backtrace).to eq(inner.backtrace)
    end

    it 'scrubs every rendering of the copy' do
      copy = scrubbed(exception: outer).exception

      [copy.to_s, copy.inspect, copy.detailed_message, copy.full_message(highlight: false)].each do |text|
        expect(text).not_to include(secret)
      end
    end

    it 'scrubs what a class-level inspect renders from its own state' do
      klass = Class.new(StandardError) do
        def initialize(message, response) = (super(message); @response = response)
        def inspect = "#<#{self.class} response=#{@response.inspect}>"
      end

      copy = scrubbed(exception: klass.new("down #{dirty_uri}", { url: dirty_uri })).exception

      expect(copy.inspect).to include(clean_uri)
      expect(copy.inspect).not_to include(secret)
    end

    it 'leaves the original exception and its cause untouched' do
      scrubbed(exception: outer)

      expect(outer.message).to include(secret)
      expect(outer.cause).to equal(inner)
      expect(inner.message).to include(secret)
      expect(outer.singleton_methods).to be_empty
    end

    it 'copies a frozen exception without touching it' do
      frozen = raised(RuntimeError, "down: #{dirty_uri}").freeze

      copy = scrubbed(exception: frozen).exception

      expect(copy.message).to eq("down: #{clean_uri}")
      expect(frozen).to be_frozen
      expect(frozen.message).to include(secret)
    end

    it 'keeps the exception object when no message in the chain changes' do
      clean = raised(RuntimeError, 'plain failure', cause: raised(ArgumentError, 'https://example.com/ok'))

      expect(scrubbed(exception: clean).exception).to equal(clean)
    end

    it 'copies the chain when only a cause changes' do
      ex   = raised(RuntimeError, 'plain failure', cause: inner)
      copy = scrubbed(exception: ex).exception

      expect(copy).not_to equal(ex)
      expect(copy.message).to eq('plain failure')
      expect(copy.cause.message).to eq("bad option in #{clean_uri}")
    end

    it 'stops at a cycle in a hand-built chain' do
      linked = Class.new(StandardError) do
        attr_accessor :link

        def cause = link
      end
      a      = linked.new("a #{dirty_uri}")
      b      = linked.new("b #{dirty_uri}")
      a.link = b
      b.link = a

      copy = scrubbed(exception: a).exception

      expect([copy.message, copy.cause.message]).to eq(["a #{clean_uri}", "b #{clean_uri}"])
      expect(copy.cause.cause).to be_nil
    end

    it 'cuts a chain longer than MAX_EXCEPTION_CHAIN, even with nothing to scrub' do
      chain = (1..(described_class::MAX_EXCEPTION_CHAIN + 5)).inject(nil) do |cause, i|
        raised(RuntimeError, "link #{i}", cause: cause)
      end

      copy  = scrubbed(exception: chain).exception
      links = []
      while copy
        links << copy
        copy = copy.cause
      end

      expect(links.size).to eq(described_class::MAX_EXCEPTION_CHAIN)
      expect(links.last.cause).to be_nil
      expect(described_class::MAX_EXCEPTION_CHAIN).to eq(SemanticLogger::Log::MAX_EXCEPTIONS_TO_UNWRAP)
    end
  end

  describe 'encodings' do
    it 'scrubs an ASCII-8BIT string with a URI' do
      expect(scrubbed(message: "raw #{dirty_uri}".b).message).to eq("raw #{clean_uri}")
    end

    it 'returns an ASCII-8BIT string without "://" as the same object' do
      message = "raw \xFF bytes".b
      expect(scrubbed(message: message).message).to equal(message)
    end

    it 'scrubs malformed UTF-8 with a URI and returns valid UTF-8' do
      result = scrubbed(message: "bad \xFF #{dirty_uri}".dup.force_encoding('UTF-8')).message

      expect(result).to be_valid_encoding
      expect(result).not_to include(secret)
    end

    it 'returns malformed UTF-8 without "://" as the same object' do
      message = "bad \xFF bytes".dup.force_encoding('UTF-8')
      expect(scrubbed(message: message).message).to equal(message)
    end

    it 'scrubs a credential URL in UTF-16LE and UTF-32BE' do
      %w[UTF-16LE UTF-32BE].each do |encoding|
        result = scrubbed(message: "wide #{dirty_uri}".encode(encoding)).message

        expect(result).to eq("wide #{clean_uri}")
      end
    end

    it 'transcodes valid text in other encodings instead of reinterpreting its bytes' do
      { 'Windows-1252' => 'café', 'Shift_JIS' => '接続' }.each do |encoding, word|
        result = scrubbed(message: "#{word} #{dirty_uri}".encode(encoding)).message

        expect(result).to eq("#{word} #{clean_uri}")
      end
    end

    # UTF-7 and ISO-2022-JP-2 have no converter to UTF-8, and UTF-7 can
    # spell "://" in base64, so a string in one of them that holds a ":"
    # byte cannot be scrubbed reliably and is replaced.
    it 'replaces text in an encoding with no converter when it holds a ":"' do
      ["redis://u:#{secret}@db/0", "redis+ADoALwAv-u:#{secret}+AEA-db/0"].each do |text|
        message = text.dup.force_encoding('UTF-7')
        expect(scrubbed(message: message).message).to eq(described_class::UNREADABLE_SENTINEL)
      end
      expect(scrubbed(message: "x://#{secret}".dup.force_encoding('ISO-2022-JP-2')).message).to eq(described_class::UNREADABLE_SENTINEL)
    end

    it 'leaves text in an encoding with no converter alone when it has no ":"' do
      message = 'plain text'.dup.force_encoding('UTF-7')
      expect(scrubbed(message: message).message).to equal(message)
    end

    it 'returns a UTF-16LE string without "://" as the same object' do
      message = 'wide text'.encode('UTF-16LE')
      expect(scrubbed(message: message).message).to equal(message)
    end

    # The invalid byte hides the marker from a byte-level probe, but the
    # text a formatter prints can join it back into "://". Probe the
    # cleaned text instead.
    it 'scrubs a URI whose "://" is split by an invalid byte' do
      utf8   = "connect redis:\xFF//default:#{secret}@cache:6379/0".dup.force_encoding('UTF-8')
      binary = "connect redis:\xFF//default:#{secret}@cache:6379/0".b

      [utf8, binary].each do |message|
        expect(scrubbed(message: message).message).to eq('connect redis://***@cache:6379/0')
      end
    end
  end

  describe 'limits (fail closed)' do
    it 'replaces a cyclic back-reference with the cycle sentinel' do
      payload        = { url: dirty_uri }
      payload[:self] = payload
      list           = [dirty_uri]
      list << list

      expect(scrubbed(payload: payload).payload).to eq(url: clean_uri, self: described_class::CYCLE_SENTINEL)
      expect(scrubbed(payload: list).payload).to eq([clean_uri, described_class::CYCLE_SENTINEL])
      expect(payload[:self]).to equal(payload)
    end

    it 'walks a branch shared by two siblings twice rather than calling it a cycle' do
      shared = { url: dirty_uri }

      expect(scrubbed(payload: { a: shared, b: shared }).payload)
        .to eq(a: { url: clean_uri }, b: { url: clean_uri })
    end

    it 'replaces a container past MAX_DEPTH with the depth sentinel' do
      payload = (1..(described_class::MAX_DEPTH + 4)).inject(dirty_uri) { |inner, _| { n: inner } }

      result = scrubbed(payload: payload).payload

      expect(result.inspect).not_to include(secret)
      expect(result.inspect).to include(described_class::DEPTH_SENTINEL)
      expect(result.dig(*Array.new(described_class::MAX_DEPTH, :n))).to eq(described_class::DEPTH_SENTINEL)
    end

    it 'cuts an array past MAX_NODES and marks the cut' do
      list = Array.new(described_class::MAX_NODES + 500) { |i| "value #{i}" } << dirty_uri

      result = scrubbed(payload: { list: list }).payload[:list]

      expect(result.size).to be < list.size
      expect(result.last).to eq(described_class::NODES_SENTINEL)
      expect(result.inspect).not_to include(secret)
    end

    it 'cuts a hash past MAX_NODES and marks the cut' do
      hash = Array.new(described_class::MAX_NODES + 500) { |i| [:"k#{i}", 'clean'] }.to_h

      result = scrubbed(payload: hash).payload

      expect(result.size).to be < hash.size
      expect(result[described_class::TRUNCATED_KEY]).to eq(described_class::NODES_SENTINEL)
    end

    it 'replaces an oversized string containing "://" with the oversized sentinel' do
      big = ('a' * described_class::MAX_STRING_BYTES) + " #{dirty_uri}"

      expect(scrubbed(message: big, payload: { big: big }).payload[:big]).to eq(described_class::OVERSIZED_SENTINEL)
      expect(scrubbed(message: big).message).to eq(described_class::OVERSIZED_SENTINEL)
    end

    it 'returns an oversized string without "://" as the same object' do
      big = 'a' * (described_class::MAX_STRING_BYTES + 1)
      expect(scrubbed(message: big).message).to equal(big)
    end

    it 'replaces strings past the event scan budget with the budget sentinel' do
      chunk   = ('a' * (described_class::MAX_STRING_BYTES - 100)) + " #{dirty_uri}"
      fits    = described_class::MAX_EVENT_SCAN_BYTES / chunk.bytesize
      payload = Array.new(fits + 2) { chunk }

      result = scrubbed(message: "m #{dirty_uri}", payload: payload).payload

      expect(result.first).to end_with(clean_uri)
      expect(result.last).to eq(described_class::BUDGET_SENTINEL)
      expect(result.inspect).not_to include(secret)
    end

    # The message and the exception are scanned before tags and payload, so
    # URI-heavy payload strings cannot spend the budget they need.
    it 'scans the exception before the payload' do
      tail = " see #{dirty_uri}"
      body = ('x' * (described_class::MAX_STRING_BYTES - tail.bytesize)) + tail
      ex   = raised(IOError, "upstream #{dirty_uri} returned 502")

      log = scrubbed(message: 'provider failed', payload: { bodies: Array.new(5) { body } }, exception: ex)

      expect(log.exception.message).to eq("upstream #{clean_uri} returned 502")
      expect(log.payload[:bodies].last).to eq(described_class::BUDGET_SENTINEL)
    end

    # Once the budget is spent, a payload exception becomes the sentinel
    # String instead of a copy whose messages are all sentinels.
    it 'stops copying payload exceptions once the scan budget is spent' do
      big    = ('a' * (described_class::MAX_STRING_BYTES - 100)) + " #{dirty_uri}"
      errors = Array.new(8) { raised(RuntimeError, big) }

      result = scrubbed(payload: { errors: errors }).payload[:errors]

      # Each copy is charged for its message and its inspect: two fit.
      expect(result.first(2)).to all(be_a(RuntimeError))
      expect(result.last).to eq(described_class::BUDGET_SENTINEL)
      expect(result.inspect).not_to include(secret)
    end

    it 'counts every exception link toward MAX_NODES' do
      chain  = raised(RuntimeError, 'c', cause: raised(RuntimeError, 'b', cause: raised(RuntimeError, 'a')))
      errors = Array.new(described_class::MAX_NODES) { chain }

      result = scrubbed(payload: { errors: errors }).payload[:errors]

      expect(result.size).to be < (described_class::MAX_NODES / 3) + 3
      expect(result.last).to eq(described_class::NODES_SENTINEL)
    end

    # The byte caps assume the redaction regex runs in linear time. On Ruby
    # 3.4 it does only through Onigmo's match cache; without it the pattern
    # is quadratic.
    it 'relies on a linear-time redaction pattern' do
      expect(Regexp.linear_time?(Onetime::Utils::Strings::EMBEDDED_URI_PATTERN)).to be(true)
    end
  end

  describe 'scrub failure' do
    let(:ex) { raised(RuntimeError, "boom #{dirty_uri}") }

    before do
      allow(Onetime::Utils).to receive(:redact_uris_in_text).and_raise(RuntimeError, "internal #{dirty_uri}")
    end

    it 'withholds the event instead of raising' do
      log = build_log(message: "m #{dirty_uri}", payload: { e: dirty_uri }, exception: ex,
        tags: [dirty_uri], named_tags: { u: dirty_uri }
      )

      expect { described_class.call(log) }.not_to raise_error
      expect(log.message).to eq(described_class::FAILURE_MESSAGE)
      expect(log.payload).to eq(log_scrub_error: 'RuntimeError')
      expect([log.exception, log.tags, log.named_tags]).to eq([nil, [], {}])
    end

    # Semantic Logger would swallow it anyway and print an unscrubbed line
    # through its internal logger, so it is not re-raised.
    it 'withholds on a non-StandardError without raising' do
      interrupt = Class.new(Exception)
      allow(Onetime::Utils).to receive(:redact_uris_in_text).and_raise(interrupt)
      log       = build_log(message: "m #{dirty_uri}")

      expect { described_class.call(log) }.not_to raise_error
      expect(log.message).to eq(described_class::FAILURE_MESSAGE)
      expect(log.payload).to eq(log_scrub_error: interrupt.name.to_s)
    end
  end

  describe '.register!' do
    around do |example|
      was_registered = described_class.registered?
      SemanticLogger::Logger.subscribers&.delete(described_class)
      example.run
    ensure
      SemanticLogger::Logger.subscribers&.delete(described_class)
      described_class.register! if was_registered
    end

    it 'registers once however often it runs' do
      expect(described_class.register!).to be(true)
      expect(described_class.register!).to be(false)

      expect(SemanticLogger::Logger.subscribers.count { |s| s.equal?(described_class) }).to eq(1)
    end

    # Config loading and early initializers log before SetupLoggers runs.
    # The boot is stopped at its guard, which comes before Config.load, so
    # nothing past registration runs.
    it 'is registered at the very start of Onetime.boot!, before the config loads' do
      registered_at_guard = nil
      original_env        = OT.env
      allow(OT::Config).to receive(:load)
      allow(Onetime).to receive(:boot_guard!) do
        registered_at_guard = described_class.registered?
        false
      end

      begin
        Onetime.boot!
      ensure
        OT.env = original_env
      end

      expect(registered_at_guard).to be(true)
      expect(OT::Config).not_to have_received(:load)
    end
  end

  # Real appenders and real formatters, with the scrubber registered as the
  # initializer registers it. The spec run uses the synchronous processor
  # (spec_helper), and each example flushes before reading.
  describe 'end to end through Semantic Logger appenders' do
    let(:text_io) { StringIO.new }
    let(:json_io) { StringIO.new }
    let(:logger) { SemanticLogger['LogScrubberSpec'].tap { |l| l.level = :trace } }
    let(:appenders) { [] }

    around do |example|
      was_registered = described_class.registered?
      described_class.register!
      example.run
    ensure
      appenders.each { |appender| SemanticLogger.remove_appender(appender) }
      SemanticLogger::Logger.subscribers&.delete(described_class) unless was_registered
    end

    def add_appender(io, formatter)
      filter = /\ALogScrubberSpec\z/
      SemanticLogger.add_appender(io: io, formatter: formatter, level: :trace, filter: filter).tap { |a| appenders << a }
    end

    # Backtraces trimmed to keep lane output short: an appender added by an
    # earlier boot in the same process prints these events too.
    def log_failure
      cause = raised(ArgumentError, "bad #{dirty_uri}").tap { |e| e.set_backtrace(e.backtrace.first(2)) }
      ex    = raised(message_override_class, 'connect failed', dirty_uri, cause: cause)
      ex.set_backtrace(ex.backtrace.first(2))
      logger.error("Redis unavailable at #{dirty_uri}", error: ex.message, uri: URI("https://u:#{secret}@h.example/x?q=1"), exception: ex)
      SemanticLogger.flush
      ex
    end

    it 'writes a scrubbed line with the default text formatter' do
      add_appender(text_io, :default)
      log_failure

      expect(text_io.string).to include("Redis unavailable at #{clean_uri}", 'LogScrubberSpec::ConnectionError')
      expect(text_io.string).to include('Cause: ArgumentError')
      expect(text_io.string).not_to include(secret)
    end

    # The configured default formatter (etc/defaults/logging.defaults.yaml).
    it 'writes a scrubbed line with the color formatter' do
      add_appender(text_io, :color)
      log_failure

      expect(text_io.string).to include("Redis unavailable at #{clean_uri}", 'Cause: ArgumentError')
      expect(text_io.string).not_to include(secret)
    end

    it 'keeps a URI split by an ANSI escape scrubbed after the JSON formatter cleans the message' do
      add_appender(json_io, :json)
      logger.error("connect redis:\e[0m//default:#{secret}@cache:6379/0?password=#{secret}")
      SemanticLogger.flush

      expect(JSON.parse(json_io.string.lines.last)['message']).to eq('connect redis://***@cache:6379/0?***')
    end

    it 'writes a scrubbed document with the JSON formatter' do
      add_appender(json_io, :json)
      log_failure

      doc = JSON.parse(json_io.string.lines.last)
      expect(doc['message']).to eq("Redis unavailable at #{clean_uri}")
      expect(doc['payload']).to eq('error' => "connect failed (#{clean_uri}", 'uri' => 'https://***@h.example/x?***')
      expect(doc.dig('exception', 'name')).to eq('LogScrubberSpec::ConnectionError')
      expect(doc.dig('exception', 'cause', 'message')).to eq("bad #{clean_uri}")
      expect(json_io.string).not_to include(secret)
    end

    it 'hands both appenders the same scrubbed event and leaves the original intact' do
      add_appender(text_io, :default)
      add_appender(json_io, :json)

      ex = log_failure

      expect([text_io.string, json_io.string]).to all(include(clean_uri))
      expect(text_io.string + json_io.string).not_to include(secret)
      expect(ex.message).to include(secret)
    end
  end
end
