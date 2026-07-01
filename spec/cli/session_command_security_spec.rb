# spec/cli/session_command_security_spec.rb
#
# frozen_string_literal: true
#
# Regression coverage for GitHub issue onetimesecret#3498, item 1:
# "Unsafe deserialization" of Redis-sourced session bytes.
#
# Security property locked in here:
#   The session loaders must NEVER call Marshal.load on bytes pulled from
#   Redis. Marshal walks (and instantiates) its entire object graph BEFORE
#   it can raise, so a rescue around it offers no protection against a
#   crafted gadget-chain payload planted at a session key. The fix replaces
#   Marshal.load with JSON.parse plus a safe rescue fallback.
#
# These tests FAIL if production reverts to `Marshal.load(raw_data)`:
#   (a) `expect(Marshal).not_to receive(:load)` would trip, and
#   (b) the return value would be the reconstructed Ruby object the Marshal
#       blob encoded, not the safe `{'_raw' => ...}` fallback Hash.
#
# Production code under test:
#   lib/onetime/cli/session_command.rb#load_session_data  (L46-60)
#   lib/middleware/session_debugger.rb#verify_redis_state  (L190-198)

require_relative 'cli_spec_helper'
require_relative '../../lib/middleware/session_debugger'

RSpec.describe 'Session deserialization security (issue #3498 item 1)', type: :cli do
  # A named gadget type so Marshal.dump can serialize an instance of it.
  # (Marshal cannot dump anonymous classes.) Reconstructing this object is
  # exactly what the vulnerable Marshal.load path would do, and exactly what
  # the fix must NOT do.
  #
  # Defined via stub_const so it is scoped to this example group and does NOT
  # leak as a top-level constant into the rest of the suite. We give it a real
  # body (a class definition) so Marshal can serialize/round-trip instances.
  before do
    stub_const('SessionGadgetProbe', Class.new do
      attr_reader :pwned

      def initialize(pwned)
        @pwned = pwned
      end
    end)
  end

  # load_session_data is an instance method of module
  # Onetime::CLI::SessionHelpers. Unit-test it by mixing the module into an
  # anonymous host class so we exercise the method in isolation, free of the
  # Dry::CLI command plumbing.
  let(:host) { Class.new { include Onetime::CLI::SessionHelpers }.new }
  let(:dbclient) { double('Redis') }
  let(:key) { 'session:40b536f31d425980' }

  describe 'Onetime::CLI::SessionHelpers#load_session_data' do
    context 'with a crafted Marshal payload as the Redis value (malicious)' do
      # A real Marshal.dump blob. If the loader were to call Marshal.load on
      # this, it would reconstruct the Struct instance below. The fix must
      # never do that.
      let(:marshal_blob) { Marshal.dump(SessionGadgetProbe.new('rce')) }

      before do
        allow(dbclient).to receive(:get).with(key).and_return(marshal_blob)
      end

      it 'never invokes Marshal.load' do
        # This is the core regression guard: the old code called
        # Marshal.load(raw_data); the fix must not touch Marshal at all.
        expect(Marshal).not_to receive(:load)
        host.load_session_data(dbclient, key)
      end

      it 'returns the safe {\'_raw\' => truncated} fallback Hash, not the reconstructed object' do
        result = host.load_session_data(dbclient, key)

        expect(result).to be_a(Hash)
        expect(result).to eq('_raw' => marshal_blob[0..200])
        # Critically, NOT the object the Marshal blob would have produced.
        expect(result).not_to be_a(SessionGadgetProbe)
        expect(result).not_to respond_to(:pwned)
      end
    end

    context 'with arbitrary non-JSON binary bytes (malicious)' do
      let(:binary_blob) { "\xFF\x00garbage\x01\x02".b }

      before do
        allow(dbclient).to receive(:get).with(key).and_return(binary_blob)
      end

      it 'does not raise and returns the safe fallback Hash' do
        expect(Marshal).not_to receive(:load)
        result = nil
        expect { result = host.load_session_data(dbclient, key) }.not_to raise_error
        expect(result).to be_a(Hash)
        expect(result.keys).to eq(['_raw'])
      end
    end

    context 'truncation of the fallback value' do
      # A Marshal blob comfortably longer than 201 bytes so we can pin that
      # the fallback echoes at most raw_data[0..200] and never an unbounded
      # blob back to the operator's terminal.
      let(:big_blob) { Marshal.dump('A' * 5000) }

      before do
        allow(dbclient).to receive(:get).with(key).and_return(big_blob)
      end

      it 'truncates the fallback to exactly raw_data[0..200] (<= 201 chars)' do
        result = host.load_session_data(dbclient, key)
        expect(result['_raw']).to eq(big_blob[0..200])
        expect(result['_raw'].length).to be <= 201
      end
    end

    context 'with valid JSON session data (legitimate, positive case)' do
      let(:valid_json) do
        JSON.generate('authenticated' => true, 'email' => 'a@b.com')
      end

      before do
        allow(dbclient).to receive(:get).with(key).and_return(valid_json)
      end

      it 'round-trips to a Hash equal to the parsed structure' do
        result = host.load_session_data(dbclient, key)
        expect(result).to be_a(Hash)
        expect(result).to eq('authenticated' => true, 'email' => 'a@b.com')
      end

      it 'does not use Marshal even on legitimate input' do
        expect(Marshal).not_to receive(:load)
        host.load_session_data(dbclient, key)
      end
    end

    context 'when the key is empty (guard preserved)' do
      before do
        allow(dbclient).to receive(:get).with(key).and_return(nil)
      end

      it 'returns nil' do
        expect(host.load_session_data(dbclient, key)).to be_nil
      end
    end
  end

  # lib/middleware/session_debugger.rb#verify_redis_state (L170) is reachable
  # only under ENV['DEBUG_SESSION'] (development) and behind a Familia.dbclient
  # probe. It logs and returns nil rather than yielding a value, so we cannot
  # assert on a return value directly. Instead we drive the REAL private method
  # end-to-end with a stubbed dbclient + logger, and:
  #
  #   (a) assert Marshal.load is never called for the whole invocation, and
  #   (b) spy the `logger.debug 'Redis session found', {... parsed: ...}`
  #       payload to confirm the parsed value took the SAFE fallback branch
  #       (raw String -> parsed.is_a?(Hash) == false), NOT a reconstructed
  #       object/Hash, when fed a Marshal blob.
  #
  # The production parse expression (session_debugger L194-198):
  #
  #     parsed = begin
  #                JSON.parse(data)
  #              rescue StandardError
  #                data
  #              end
  #
  # A revert of this method to `Marshal.load(data)` fails (a): Marshal.load
  # would be invoked. It also fails (b): the blob would parse into a Hash, so
  # the logged `parsed:` flag would flip to true.
  describe 'Rack::SessionDebugger#verify_redis_state (real production method)' do
    let(:session_id) { 'sid' }
    # The first matched pattern verify_redis_state probes is "session:#{sid}".
    let(:matched_key) { "session:#{session_id}" }
    let(:redis) { instance_double('Redis') }
    let(:logger_spy) { instance_spy('SemanticLogger::Logger') }

    # Construct the REAL middleware. Force DEBUG_SESSION on (the constructor
    # reads ENV['DEBUG_SESSION']); also belt-and-braces set @enabled directly.
    let(:middleware) do
      mw = Rack::SessionDebugger.new(->(_env) { [200, {}, []] })
      mw.instance_variable_set(:@enabled, true)
      mw
    end

    before do
      ENV['DEBUG_SESSION'] = 'true'

      # Probe behaviour: the first key pattern ("session:sid") exists; the
      # method short-circuits there with `return`, so only this branch runs.
      allow(redis).to receive(:exists).and_return(0)
      allow(redis).to receive(:exists).with(matched_key).and_return(1)
      allow(redis).to receive(:ttl).with(matched_key).and_return(3600)
      allow(Familia).to receive(:dbclient).and_return(redis)

      # Silence/spy the middleware logger so the debug call is harmless and we
      # can inspect the payload it was handed.
      allow(middleware).to receive(:logger).and_return(logger_spy)
    end

    after { ENV.delete('DEBUG_SESSION') }

    context 'when the stored Redis value is a crafted Marshal blob (malicious)' do
      let(:marshal_blob) { Marshal.dump(SessionGadgetProbe.new('rce')) }

      before do
        allow(redis).to receive(:get).with(matched_key).and_return(marshal_blob)
      end

      it 'never invokes Marshal.load while inspecting the Redis value' do
        # Core regression guard against a revert to Marshal.load(data).
        expect(Marshal).not_to receive(:load)
        middleware.send(:verify_redis_state, session_id, 'after')
      end

      it 'logs the SAFE fallback: parsed is the raw String, not a Hash' do
        middleware.send(:verify_redis_state, session_id, 'after')

        # The middleware logs `parsed: parsed.is_a?(Hash)`. On the Marshal
        # blob the JSON.parse raises and the fallback is the raw String, so the
        # logged flag MUST be false. A Marshal.load revert would reconstruct a
        # Hash/object here and flip this to true.
        expect(logger_spy).to have_received(:debug).with(
          'Redis session found',
          hash_including(
            key: matched_key,
            ttl: 3600,
            parsed: false,
          ),
        )
      end
    end

    context 'when the stored Redis value is valid JSON (legitimate, positive case)' do
      let(:json_blob) { JSON.generate('authenticated' => true) }

      before do
        allow(redis).to receive(:get).with(matched_key).and_return(json_blob)
      end

      it 'parses to a Hash and logs parsed: true without touching Marshal' do
        expect(Marshal).not_to receive(:load)
        middleware.send(:verify_redis_state, session_id, 'after')

        expect(logger_spy).to have_received(:debug).with(
          'Redis session found',
          hash_including(key: matched_key, parsed: true),
        )
      end
    end
  end
end
