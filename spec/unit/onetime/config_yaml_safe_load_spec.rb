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
# Follow-up to #3498: the loaders permit_classes are [Symbol, Date, Time] (the
# issue's own recommendation), so an unquoted date/time no longer raises
# Psych::DisallowedClass and breaks boot. Arbitrary Ruby objects (!ruby/object)
# stay rejected. The runtime loader and the config validator
# (operations/config/validate.rb) keep this list symmetric so a config that
# validates also boots.
#
# These tests drive the REAL production loaders and FAIL if production reverts
# any of them back to bare YAML.load / YAML.unsafe_load:
#   - lib/onetime/config.rb#load_yaml_with_erb (L278)
#   - lib/onetime/utils/enumerables.rb#deep_clone (L111)
#   - lib/onetime/initializers/setup_loggers.rb#load_logging_config (L105, safe_load at L114/L120)
#   - lib/onetime/operations/config/validate.rb#load_config (the config
#     validator's loader — the 4th YAML.safe_load site the #3498 follow-up
#     widened to [Symbol, Date, Time]; it RESCUES Psych::DisallowedClass and
#     returns nil rather than raising)
#
# Each of these is invoked through its own public/private production entry point
# (via #send for private methods), NOT via a local mirror or a direct
# YAML.safe_load call. A YAML.safe_load-only "sanity check" block is retained at
# the bottom but is explicitly labelled as stdlib-only (it cannot fail on a prod
# revert and is not a regression test).

require 'spec_helper'
require 'tempfile'
require 'onetime/initializers/setup_loggers'
require 'onetime/operations/config/validate'

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
    # YAML.safe_load(..., permitted_classes: [Symbol, Date, Time], aliases: true).
    #
    # We stub ConfigResolver so the loader reads our controlled payload, then
    # invoke the private instance method on a real instance.
    #
    # Regression-sensitivity (verified against scratch reverts of the real
    # method, without touching the production file — Ruby 3.4.9 / Psych 5.2.6):
    #   * Revert to bare YAML.load  (permitted_classes: [Symbol, Date, Time],
    #     aliases:FALSE): the anchor/alias POSITIVE case below raises
    #     Psych::AliasesNotEnabled, so 'loads to a Hash' FAILS. (This is the
    #     MUST-FIX scenario: on this Psych, YAML.load == safe_load with
    #     [Symbol, Date, Time] and aliases:false, so the alias positive case —
    #     not the object payload — is what pins the revert.)
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

    it 'permits Symbol values (permitted_classes: [Symbol, Date, Time])' do
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

    it 'loads an unquoted Date value as a Date instance (permitted_classes includes Date)' do
      # Follow-up to #3498: the loader permits Symbol, Date and Time so an
      # unquoted date/time no longer raises Psych::DisallowedClass and breaks
      # boot. (This INVERTS the earlier [Symbol]-only rejection pin.)
      content = "expires: 2026-01-02\n"
      with_yaml_file(content) do |path|
        result = Onetime::Config.send(:load_yaml_with_erb, path)
        expect(result['expires']).to be_a(Date)
        expect(result['expires']).to eq(Date.new(2026, 1, 2))
      end
    end

    it 'loads an unquoted timestamp as a Time instance (permitted_classes includes Time)' do
      content = "at: 2026-01-02 03:04:05\n"
      with_yaml_file(content) do |path|
        result = Onetime::Config.send(:load_yaml_with_erb, path)
        expect(result['at']).to be_a(Time)
      end
    end

    it 'STILL rejects a !ruby/object:Gem::Requirement tag (arbitrary objects stay denied)' do
      # Widening to Date/Time must NOT widen to arbitrary Ruby objects.
      with_yaml_file(MALICIOUS_YAML) do |path|
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

    it 'round-trips Date and Time values (permitted_classes includes Date/Time)' do
      # Follow-up to #3498: deep_clone's safe_load permits Date and Time so a
      # config carrying date/time values survives the YAML.dump/safe_load clone
      # round-trip instead of raising Psych::DisallowedClass.
      date = Date.new(2026, 1, 2)
      time = Time.utc(2026, 1, 2, 3, 4, 5)
      orig = { 'expires' => date, 'at' => time, sym: :value }
      clone = Onetime::Utils::Enumerables.deep_clone(orig)

      expect(clone['expires']).to be_a(Date)
      expect(clone['expires']).to eq(date)
      expect(clone['at']).to be_a(Time)
      expect(clone['at']).to eq(time)
      expect(clone[:sym]).to eq(:value)
    end

    it 'STILL rejects a non-serializable native object (Proc) as OT::Problem' do
      # Arbitrary Ruby objects remain denied even after widening to Date/Time:
      # the Proc tag is not permitted, so safe_load raises Psych::DisallowedClass
      # which deep_clone re-raises as OT::Problem.
      expect {
        Onetime::Utils::Enumerables.deep_clone({ bad: -> { 1 } })
      }.to raise_error(OT::Problem)
    end

    it 'wraps a serialization failure as OT::Problem (the rescue path)' do
      # On this Ruby/Psych (3.4.9 / 5.2.6), YAML.dump does NOT raise for a Proc:
      # it succeeds and emits `!ruby/object:Proc {}`. The OT::Problem instead
      # originates on the LOAD side — YAML.safe_load(permitted_classes:
      # [Symbol, Date, Time]) raises Psych::DisallowedClass for the Proc tag,
      # which deep_clone rescues and re-raises as OT::Problem. (So this
      # exercises the safe_load guard, not a YAML.dump TypeError.)
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

  describe 'Onetime::Operations::Config::Validate#load_config (REAL production loader)' do
    # This block drives the genuine private method
    # Onetime::Operations::Config::Validate#load_config
    # (lib/onetime/operations/config/validate.rb:104) — the 4th YAML.safe_load
    # site the #3498 follow-up widened to [Symbol, Date, Time]. Unlike the other
    # three loaders, load_config RESCUES Psych::DisallowedClass and returns nil
    # (it does NOT raise out), so the assertions key off the return value:
    #   * an unquoted Date loads as a Date instance (proves Date is permitted; if
    #     the site reverted to [Symbol] this case would be DisallowedClass —
    #     rescued — and return nil, so it is regression-sensitive);
    #   * a !ruby/object payload returns nil (rejected/not materialized — proves
    #     no dangerous widening to arbitrary Ruby objects).
    #
    # load_config only uses the path argument it is handed, so we build a real
    # instance with placeholder paths and invoke the private method via #send.
    def load_config_via_production(yaml_content)
      validator = Onetime::Operations::Config::Validate.new(
        config_path: '/nonexistent/placeholder-config.yaml',
        schema_path: '/nonexistent/placeholder-schema.json',
        progress: nil,
      )
      with_yaml_file(yaml_content) do |path|
        validator.send(:load_config, path)
      end
    end

    it 'loads an unquoted Date value as a Date instance (permitted_classes includes Date)' do
      # Regression pin: on a revert to [Symbol] this would be a rescued
      # Psych::DisallowedClass and load_config would return nil instead.
      result = load_config_via_production("some_date: 2026-01-02\n")
      expect(result).to be_a(Hash)
      expect(result['some_date']).to be_a(Date)
      expect(result['some_date']).to eq(Date.new(2026, 1, 2))
    end

    it 'returns nil (rejected, not materialized) for a !ruby/object:Gem::Requirement payload' do
      # Widening to Date/Time must NOT widen to arbitrary Ruby objects: the tag
      # raises Psych::DisallowedClass, which load_config rescues to nil. Under a
      # YAML.unsafe_load revert this would instead be a Gem::Requirement instance.
      result = load_config_via_production(MALICIOUS_YAML)
      expect(result).to be_nil
    end
  end

  describe 'Onetime::Config#coerce_ttl_seconds (private) — TTL fields reject Date/Time' do
    # #3561 review follow-up to #3498: safe_load now permits Date/Time so an
    # unquoted date in *other* config fields doesn't break boot. But a date/time
    # in a NUMERIC TTL field is a quoting mistake with a security edge:
    #   * Date#to_i raises NoMethodError (crash), and
    #   * Time#to_i silently yields ~56yr (a decades-long secret TTL).
    # coerce_ttl_seconds converts both into an actionable OT::ConfigError while
    # leaving legitimate Integer/Float/String values coercing to seconds. This is
    # the guard after_load routes site.secret_options.default_ttl and
    # features.incoming.default_ttl through.
    def coerce(value, field = 'site.secret_options.default_ttl')
      Onetime::Config.send(:coerce_ttl_seconds, value, field)
    end

    it 'rejects a bare Date with an actionable OT::ConfigError (not NoMethodError)' do
      expect {
        coerce(Date.new(2026, 1, 2))
      }.to raise_error(OT::ConfigError, /must be a number of seconds/)
    end

    it 'rejects a bare Time with OT::ConfigError (not a silent ~56yr TTL)' do
      # The real regression this PR closes: Time#to_i would otherwise succeed
      # silently and mint a decades-long TTL.
      expect {
        coerce(Time.utc(2026, 1, 2, 3, 4, 5))
      }.to raise_error(OT::ConfigError, /not a date\/time/)
    end

    it 'names the offending field in the error message' do
      expect {
        coerce(Date.new(2026, 1, 2), 'features.incoming.default_ttl')
      }.to raise_error(OT::ConfigError, /features\.incoming\.default_ttl/)
    end

    it 'leaves a legitimate Integer TTL untouched' do
      expect(coerce(604_800)).to eq(604_800)
    end

    it 'coerces a Float TTL to Integer seconds' do
      expect(coerce(604_800.0)).to eq(604_800)
    end

    it 'coerces a numeric String TTL (ERB env-var form) to Integer seconds' do
      expect(coerce('604800')).to eq(604_800)
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
