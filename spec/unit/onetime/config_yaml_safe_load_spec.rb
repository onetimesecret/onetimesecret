# spec/unit/onetime/config_yaml_safe_load_spec.rb
#
# frozen_string_literal: true

# Regression coverage for GitHub issue onetimesecret#3498 (item 4):
#   YAML.load -> YAML.safe_load hardening.
#
# Security property locked in here:
#   Config/logger YAML loading and the deep_clone round-trip must use SAFE
#   loading. A YAML document carrying a Ruby-object tag (e.g.
#   !ruby/object:Gem::Requirement) must be REJECTED (Psych::DisallowedClass,
#   surfaced as OT::Problem for deep_clone), NOT instantiated. Legitimate
#   config (string/symbol keys, nested hashes, anchors/aliases) must still
#   load and clone correctly.
#
# These tests drive the REAL production loaders and FAIL if production reverts
# any of them back to bare YAML.load / YAML.unsafe_load:
#   - lib/onetime/config.rb#load_yaml_with_erb (L278)
#   - lib/onetime/utils/enumerables.rb#deep_clone (L111)
#   - lib/onetime/initializers/setup_loggers.rb#load_logging_config (L105, safe_load at L114/L120)
#
# Each of these is invoked through its own public/private production entry point
# (via #send for private methods), NOT via a local mirror or a direct
# YAML.safe_load call. A YAML.safe_load-only "sanity check" block is retained at
# the bottom but is explicitly labelled as stdlib-only (it cannot fail on a prod
# revert and is not a regression test).

require 'spec_helper'
require 'tempfile'
require 'onetime/initializers/setup_loggers'

RSpec.describe 'Issue #3498 item 4: YAML safe loading hardening' do
  # Helper: write +content+ to a temp .yaml file, yield its path, clean up.
  def with_yaml_file(content)
    file = Tempfile.new(['ots-config-3498', '.yaml'])
    file.write(content)
    file.flush
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  # A YAML payload that, under the vulnerable bare YAML.load, would instantiate
  # an arbitrary Ruby object. Under safe_load it must raise Psych::DisallowedClass.
  MALICIOUS_YAML = "--- !ruby/object:Gem::Requirement\nrequirements: []\n"

  describe 'Onetime::Initializers::SetupLoggers#load_logging_config (REAL production loader)' do
    # This block drives the genuine production method
    # Onetime::Initializers::SetupLoggers#load_logging_config
    # (lib/onetime/initializers/setup_loggers.rb:105), NOT a local mirror and
    # NOT a direct YAML.safe_load call. It reads file paths via
    # Onetime::Utils::ConfigResolver, runs each file through ERB, then
    # YAML.safe_load(..., permitted_classes: [Symbol], aliases: true).
    #
    # We stub ConfigResolver so the loader reads our controlled payload, then
    # invoke the private instance method on a real instance.
    #
    # Regression-sensitivity (verified against scratch reverts of the real
    # method, without touching the production file — Ruby 3.4.9 / Psych 5.2.6):
    #   * Revert to bare YAML.load  (permitted_classes: [Symbol], aliases:FALSE):
    #     the anchor/alias POSITIVE case below raises Psych::AliasesNotEnabled,
    #     so 'loads to a Hash' FAILS. (This is the MUST-FIX scenario: on this
    #     Psych, YAML.load == safe_load with [Symbol] and aliases:false, so the
    #     alias positive case — not the object payload — is what pins the revert.)
    #   * Revert to YAML.unsafe_load: the malicious !ruby/object payload below
    #     is materialized into a Gem::Requirement instead of raising, so the
    #     NEGATIVE case FAILS.
    let(:resolver) { Onetime::Utils::ConfigResolver }

    # Build a real instance (Initializer#initialize takes no args). The method
    # under test is a private instance method, so we invoke it via #send.
    def load_via_production(defaults_yaml)
      file = Tempfile.new(['ots-logging-3498', '.yaml'])
      file.write(defaults_yaml)
      file.flush
      file.close
      allow(resolver).to receive(:defaults_path).with('logging').and_return(file.path)
      allow(resolver).to receive(:resolve).with('logging').and_return(nil)
      Onetime::Initializers::SetupLoggers.new.send(:load_logging_config)
    ensure
      file&.unlink
    end

    it 'REJECTS a malicious !ruby/object logging config instead of materializing it (negative)' do
      expect {
        load_via_production(MALICIOUS_YAML)
      }.to raise_error(Psych::DisallowedClass)
    end

    it 'does not materialize an arbitrary Ruby object from a malicious logging config' do
      result = begin
        load_via_production(MALICIOUS_YAML)
      rescue Psych::DisallowedClass
        :rejected
      end
      # Under a YAML.unsafe_load revert this would be a Gem::Requirement instance.
      expect(result).to eq(:rejected)
    end

    it 'loads a normal logging YAML (symbols, nested hashes, anchor/alias) to a Hash (positive)' do
      # The anchor (&b) / alias (*b) here is the regression pin for a bare
      # YAML.load revert: aliases:false would raise Psych::AliasesNotEnabled.
      content = <<~YAML
        default_level: :info
        formatter: :json
        loggers:
          base: &b
            level: :debug
          Auth: *b
          Secret:
            level: :trace
      YAML
      result = load_via_production(content)

      expect(result).to be_a(Hash)
      expect(result['default_level']).to eq(:info)
      expect(result['formatter']).to eq(:json)
      expect(result['loggers']['base']).to eq({ 'level' => :debug })
      # alias resolved to the same content as the anchor:
      expect(result['loggers']['Auth']).to eq({ 'level' => :debug })
      expect(result['loggers']['Secret']).to eq({ 'level' => :trace })
    end
  end

  describe 'Onetime::Config#load_yaml_with_erb (private)' do
    it 'REJECTS a Ruby-object tag instead of instantiating it (negative case)' do
      with_yaml_file(MALICIOUS_YAML) do |path|
        expect {
          Onetime::Config.send(:load_yaml_with_erb, path)
        }.to raise_error(Psych::DisallowedClass)
      end
    end

    it 'does not produce a Gem::Requirement instance from the malicious payload' do
      with_yaml_file(MALICIOUS_YAML) do |path|
        result = begin
          Onetime::Config.send(:load_yaml_with_erb, path)
        rescue Psych::DisallowedClass
          :rejected
        end
        # On the vulnerable (bare YAML.load) code this would be a
        # Gem::Requirement instance rather than :rejected.
        expect(result).to eq(:rejected)
      end
    end

    it 'loads a legitimate nested string-keyed config (positive case)' do
      content = "site:\n  host: example.com\n  list:\n    - a\n    - b\n"
      with_yaml_file(content) do |path|
        result = Onetime::Config.send(:load_yaml_with_erb, path)
        expect(result).to be_a(Hash)
        expect(result['site']['host']).to eq('example.com')
        expect(result['site']['list']).to eq(%w[a b])
      end
    end

    it 'returns {} for an empty file (the `|| {}` fallback)' do
      with_yaml_file("") do |path|
        expect(Onetime::Config.send(:load_yaml_with_erb, path)).to eq({})
      end
    end

    it 'permits Symbol values (permitted_classes: [Symbol])' do
      content = "key: :sym_value\n"
      with_yaml_file(content) do |path|
        result = Onetime::Config.send(:load_yaml_with_erb, path)
        expect(result['key']).to eq(:sym_value)
      end
    end

    it 'honors anchors/aliases (aliases: true) without raising Psych::BadAlias' do
      content = "base: &b\n  host: example.com\nclone: *b\n"
      with_yaml_file(content) do |path|
        result = Onetime::Config.send(:load_yaml_with_erb, path)
        expect(result['base']).to eq({ 'host' => 'example.com' })
        expect(result['clone']).to eq({ 'host' => 'example.com' })
      end
    end

    it 'rejects an unquoted Date value under permitted_classes: [Symbol] (regression pin)' do
      # The hardened loader only permits Symbol, so an unquoted date string that
      # bare YAML.load would have parsed into a Date object now raises. Pin this
      # so anyone re-adding Date awareness updates the test deliberately.
      content = "d: 2020-01-01\n"
      with_yaml_file(content) do |path|
        expect {
          Onetime::Config.send(:load_yaml_with_erb, path)
        }.to raise_error(Psych::DisallowedClass)
      end
    end
  end

  describe 'Onetime::Utils::Enumerables.deep_clone' do
    it 'deep-clones a nested symbol-keyed hash to an EQUAL structure (positive)' do
      orig = { a: { b: [1, 2] }, sym: :value, 'c' => [3, 4] }
      clone = Onetime::Utils::Enumerables.deep_clone(orig)
      expect(clone).to eq(orig)
    end

    it 'produces an INDEPENDENT copy (mutating the clone does not affect original)' do
      orig = { a: { b: [1, 2] }, sym: :value }
      clone = Onetime::Utils::Enumerables.deep_clone(orig)

      expect(clone).not_to equal(orig)
      expect(clone[:a]).not_to equal(orig[:a])

      clone[:a][:b] << 3
      expect(orig[:a][:b]).to eq([1, 2])
      expect(clone[:a][:b]).to eq([1, 2, 3])
    end

    it 'PRESERVES Symbol keys (not stringified) — proves the safe_load round-trip' do
      orig = { a: { b: 1 }, sym: :value }
      clone = Onetime::Utils::Enumerables.deep_clone(orig)
      expect(clone.keys).to include(:a, :sym)
      expect(clone[:a].keys).to include(:b)
    end

    it 'wraps a serialization failure as OT::Problem (the rescue path)' do
      # On this Ruby/Psych (3.4.9 / 5.2.6), YAML.dump does NOT raise for a Proc:
      # it succeeds and emits `!ruby/object:Proc {}`. The OT::Problem instead
      # originates on the LOAD side — YAML.safe_load(permitted_classes: [Symbol])
      # raises Psych::DisallowedClass for the Proc tag, which deep_clone rescues
      # and re-raises as OT::Problem. (So this exercises the safe_load guard, not
      # a YAML.dump TypeError.)
      #
      # Note: deep_clone's safe_load only ever loads its OWN YAML.dump output, so
      # a genuinely attacker-controlled malicious-payload case is structurally
      # unreachable here — the only way to reach the DisallowedClass branch is to
      # hand deep_clone a non-serializable native object (like a Proc) yourself.
      expect {
        Onetime::Utils::Enumerables.deep_clone({ bad: -> { 1 } })
      }.to raise_error(OT::Problem)
    end

    it 'enforces the max_size gate with OT::Problem' do
      big = { data: 'x' * 100 }
      expect {
        Onetime::Utils::Enumerables.deep_clone(big, max_size: 1)
      }.to raise_error(OT::Problem, /exceeds limit/)
    end
  end

  describe 'Onetime::Config#deep_clone (delegates with max_size: Float::INFINITY)' do
    it 'clones a large hash without hitting the size gate (positive)' do
      big = { 'data' => 'x' * (3 * 1024 * 1024) } # > 2MB default gate
      result = Onetime::Config.send(:deep_clone, big)
      expect(result).to eq(big)
      expect(result).not_to equal(big)
    end
  end

  describe 'YAML.safe_load stdlib sanity check (NOT a production regression test)' do
    # IMPORTANT: this block calls YAML.safe_load DIRECTLY (Ruby stdlib). It does
    # NOT exercise any production code path and therefore CANNOT fail if a
    # production loader is reverted to bare YAML.load / YAML.unsafe_load. It only
    # documents the semantics of the safe_load call shape the hardened loaders
    # use. The genuine, regression-sensitive coverage lives in:
    #   * Onetime::Initializers::SetupLoggers#load_logging_config (block above)
    #   * Onetime::Config#load_yaml_with_erb (block above)
    #   * Onetime::Utils::Enumerables.deep_clone (block above)
    # Kept purely as an executable description of expected safe_load behavior.

    it 'rejects a !ruby/object payload (stdlib behavior of the safe_load call shape)' do
      expect {
        YAML.safe_load(MALICIOUS_YAML, permitted_classes: [Symbol], aliases: true)
      }.to raise_error(Psych::DisallowedClass)
    end

    it 'still permits Symbol and resolves aliases (stdlib positive behavior)' do
      doc = "anchor: &a\n  level: :debug\nuse: *a\n"
      result = YAML.safe_load(doc, permitted_classes: [Symbol], aliases: true)
      expect(result['anchor']['level']).to eq(:debug)
      expect(result['use']['level']).to eq(:debug)
    end
  end
end
