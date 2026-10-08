# spec/unit/onetime/initializers/setup_loggers_safeguards_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Regression examples for the behavior the `destinations` block (#4683) is
# meant to leave alone outside a test run. They sit beside
# setup_loggers_spec.rb, which already pins the shipped defaults (one console
# appender on stdout / stderr, no file sink) and the audit bypass of a
# destination threshold. What is added here:
#
#   - no file is opened for a file destination that is configured but not
#     enabled;
#   - LOG_LEVEL, DEBUG_* and DEBUG_LOGGERS set the same levels as before, and
#     installing destinations changes no level;
#   - the audit sink's own logger still writes to the console when the
#     default level and the console threshold are both above info;
#   - the lane runner's LANES_APP_LOG_* variables change nothing unless
#     RACK_ENV is exactly `test`, because spec/logging.test.yaml is the only
#     file that reads them and it is only resolved then.
RSpec.describe Onetime::Initializers::SetupLoggers, 'safeguards outside a test run' do
  include_context 'with isolated log appenders'

  subject(:instance) { described_class.new }

  let(:tmpdir) { Dir.mktmpdir('setup_loggers_safeguards_spec') }
  let(:log_path) { File.join(tmpdir, 'app.log') }
  let(:console_io) { StringIO.new }
  let(:registry) { described_class.owned_appenders }
  let(:repo_root) { File.expand_path('../../../..', __dir__) }
  let(:level_env) { ['LOG_LEVEL', 'DEBUG_LOGGERS', *described_class.logger_definitions.values] }
  let(:shipped_defaults) do
    path = File.join(repo_root, 'etc', 'defaults', 'logging.defaults.yaml')
    YAML.safe_load(ERB.new(File.read(path)).result, permitted_classes: [Symbol, Date, Time], aliases: true)
  end

  # The examples set the global levels and the level variables, so both are
  # put back. A lane run with --quiet exports LOG_LEVEL and DEBUG_LOGGERS;
  # each example starts with neither.
  around do |example|
    saved_default   = SemanticLogger.default_level
    saved_backtrace = SemanticLogger.backtrace_level
    saved_env       = ENV.to_h
    level_env.each { |name| ENV.delete(name) }
    example.run
  ensure
    ENV.replace(saved_env)
    SemanticLogger.default_level   = saved_default
    SemanticLogger.backtrace_level = saved_backtrace
  end

  before do
    allow(instance).to receive(:log_device).and_return(console_io)
    allow(Onetime).to receive(:debug?).and_return(false)
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def file_sinks
    SemanticLogger.appenders.grep(described_class::FileSink)
  end

  def console_log
    console_io.string
  end

  def levels_of(cache)
    cache.transform_values(&:level)
  end

  describe 'a file destination that is not enabled' do
    # A path alone does not turn the destination on.
    [
      ['has a path and no enabled key', {}],
      ['has a path and enabled: false', { 'enabled' => false }],
      ['has a path and enabled: null', { 'enabled' => nil }],
    ].each do |label, enabled|
      it "opens no file when it #{label}" do
        config = shipped_defaults.merge(
          'destinations' => { 'console' => {}, 'file' => { 'path' => log_path, 'level' => 'trace' }.merge(enabled) },
        )

        instance.install_destinations(config)
        SemanticLogger['SetupLoggersSafeguardsSpec'].error('an error')

        expect(file_sinks).to be_empty
        expect(registry.keys).to eq([:console])
        expect(File.exist?(log_path)).to be(false)
        expect(console_log).to include('an error')
      end
    end

    it 'opens no file when the config has no file block' do
      instance.install_destinations(shipped_defaults.merge('destinations' => { 'console' => { 'enabled' => true } }))

      expect(file_sinks).to be_empty
      expect(registry.keys).to eq([:console])
    end
  end

  describe 'the default level' do
    def default_level_for(config)
      instance.send(:configure_default_level, config)
      SemanticLogger.default_level
    end

    it 'is info when neither LOG_LEVEL nor the config sets one' do
      expect(default_level_for({})).to eq(:info)
    end

    it 'is the config default_level when LOG_LEVEL is unset' do
      expect(default_level_for('default_level' => 'error')).to eq(:error)
    end

    it 'is LOG_LEVEL when both are set' do
      ENV['LOG_LEVEL'] = 'debug'

      expect(default_level_for('default_level' => 'error')).to eq(:debug)
    end

    it 'is the same with a destinations block that sets thresholds' do
      config = {
        'default_level' => 'warn',
        'destinations' => { 'console' => { 'level' => 'fatal' }, 'file' => { 'enabled' => true, 'path' => log_path, 'level' => 'trace' } },
      }

      expect(default_level_for(config)).to eq(:warn)

      instance.install_destinations(config)

      expect(SemanticLogger.default_level).to eq(:warn)
    end
  end

  describe 'category levels' do
    def cached_loggers(config)
      instance.send(:create_cached_loggers, config).tap { |cache| instance.send(:apply_env_overrides, cache) }
    end

    it 'take each defined category from the shipped config and the rest from the default level' do
      SemanticLogger.default_level = :fatal
      configured                   = shipped_defaults.fetch('loggers')

      expected = described_class.logger_definitions.keys.to_h do |name|
        [name, configured.key?(name) ? configured.fetch(name).to_sym : :fatal]
      end

      expect(expected.values.uniq.size).to be > 1
      expect(levels_of(cached_loggers(shipped_defaults))).to eq(expected)
    end

    it 'are the same with and without a destinations block, whatever its thresholds' do
      without    = levels_of(cached_loggers(shipped_defaults.except('destinations')))
      thresholds = shipped_defaults.merge(
        'destinations' => {
          'console' => { 'enabled' => true, 'level' => 'fatal' },
          'file' => { 'enabled' => true, 'path' => log_path, 'level' => 'trace' },
        },
      )

      instance.install_destinations(thresholds)

      expect(levels_of(cached_loggers(shipped_defaults))).to eq(without)
      expect(levels_of(cached_loggers(thresholds))).to eq(without)
    end

    # install_destinations is all of the appender handling; the loggers it
    # finds keep the level they had.
    it 'are not changed by installing destinations' do
      cache  = cached_loggers(shipped_defaults)
      before = levels_of(cache)

      instance.install_destinations(
        'destinations' => {
          'console' => { 'level' => 'error' },
          'file' => { 'enabled' => true, 'path' => log_path, 'level' => 'fatal' },
        },
      )

      expect(levels_of(cache)).to eq(before)
    end

    it 'still gate generation when both destinations admit every level' do
      instance.install_destinations(
        'destinations' => {
          'console' => { 'level' => 'trace' },
          'file' => { 'enabled' => true, 'path' => log_path, 'level' => 'trace' },
        },
      )
      cache = cached_loggers('loggers' => { 'Auth' => 'info', 'Sequel' => 'warn' })

      cache['Auth'].debug('auth debug')
      cache['Auth'].info('auth info')
      cache['Sequel'].info('sequel info')
      cache['Sequel'].warn('sequel warn')

      [console_log, File.read(log_path)].each do |written|
        expect(written).to include('auth info', 'sequel warn')
        expect(written).not_to include('auth debug', 'sequel info')
      end
    end

    it 'go to debug for a category whose DEBUG_* flag is set, and only that one' do
      ENV['DEBUG_SEQUEL'] = '1'

      levels = levels_of(cached_loggers('loggers' => { 'Sequel' => 'warn', 'Auth' => 'info' }))

      expect(levels).to include('Sequel' => :debug, 'Auth' => :info)
    end

    it 'take the level DEBUG_LOGGERS names, in either separator, over the config and the flag' do
      ENV['DEBUG_AUTH']    = '1'
      ENV['DEBUG_LOGGERS'] = 'Auth:error, Secret=trace,Malformed,SetupLoggersSafeguardsAdHoc:fatal'

      cache = cached_loggers('loggers' => { 'Auth' => 'info', 'Secret' => 'info', 'HTTP' => 'warn' })

      expect(levels_of(cache)).to include(
        'Auth' => :error, 'Secret' => :trace, 'HTTP' => :warn, 'SetupLoggersSafeguardsAdHoc' => :fatal
      )
      expect(cache.keys).not_to include('Malformed')
    end
  end

  # The audit sink emits through its own logger, pinned at info in the model
  # (Onetime::ColonelAuditEvent.sink_logger). setup_loggers_spec.rb covers
  # the destination threshold with a stand-in logger of the same name; these
  # use the model's logger and raise the levels around it.
  describe 'the audit sink logger' do
    let(:model) { Onetime::ColonelAuditEvent }

    around do |example|
      memoized = model.instance_variable_defined?(:@sink_logger)
      saved    = model.instance_variable_get(:@sink_logger)
      model.remove_instance_variable(:@sink_logger) if memoized
      example.run
    ensure
      model.remove_instance_variable(:@sink_logger) if model.instance_variable_defined?(:@sink_logger)
      model.instance_variable_set(:@sink_logger, saved) if memoized
    end

    def boot_levels(config)
      instance.send(:configure_default_level, config)
      instance.install_destinations(config)
      instance.send(:create_cached_loggers, config).tap { |cache| instance.send(:apply_env_overrides, cache) }
    end

    def emit_audit_event
      model.sink_logger.public_send(model::SINK_LEVEL, model::SINK_MESSAGE, { 'verb' => 'safeguards.spec' })
    end

    %w[error fatal].each do |level|
      it "writes to the console when the config default_level is #{level}" do
        cache = boot_levels(shipped_defaults.merge('default_level' => level))

        emit_audit_event
        cache['App'].info('app info')
        SemanticLogger['SetupLoggersSafeguardsSpec'].warn('uncategorised warn')

        expect(SemanticLogger.default_level).to eq(level.to_sym)
        expect(console_log).to include(described_class::AUDIT_SINK_LOGGER_NAME, model::SINK_MESSAGE, 'safeguards.spec')
        expect(console_log).not_to include('app info', 'uncategorised warn')
      end
    end

    it 'writes to the console when LOG_LEVEL is fatal and every category is raised to fatal' do
      ENV['LOG_LEVEL'] = 'fatal'
      raised           = described_class.logger_definitions.keys.to_h { |name| [name, 'fatal'] }

      cache = boot_levels(shipped_defaults.merge('loggers' => raised))
      emit_audit_event
      cache.each_value { |logger| logger.error('category error') }

      expect(console_log).to include(model::SINK_MESSAGE, 'safeguards.spec')
      expect(console_log).not_to include('category error')
    end

    it 'writes to the console when the default level and the console threshold are both fatal' do
      config = shipped_defaults.merge(
        'default_level' => 'fatal',
        'destinations' => { 'console' => { 'enabled' => true, 'level' => 'fatal' }, 'file' => { 'enabled' => false } },
      )

      boot_levels(config)
      emit_audit_event
      SemanticLogger['SetupLoggersSafeguardsSpec'].tap { |logger| logger.level = :trace }.error('below the threshold')

      expect(console_log).to include(model::SINK_MESSAGE, 'safeguards.spec')
      expect(console_log).not_to include('below the threshold')
    end

    # DEBUG_LOGGERS sets the level on a logger of that name it creates
    # itself; the model keeps its own.
    it 'writes to the console when DEBUG_LOGGERS names the audit category at fatal' do
      ENV['DEBUG_LOGGERS'] = "#{described_class::AUDIT_SINK_LOGGER_NAME}:fatal"

      boot_levels(shipped_defaults.merge('default_level' => 'fatal'))
      emit_audit_event

      expect(model.sink_logger.level).to eq(model::SINK_LEVEL)
      expect(console_log).to include(model::SINK_MESSAGE, 'safeguards.spec')
    end
  end

  # spec/logging.test.yaml turns LANES_APP_LOG_CONSOLE / LANES_APP_LOG_FILE
  # into a `destinations` block. Here it is copied into a throwaway
  # application root next to the shipped defaults, with etc/logging.yaml a
  # copy of those defaults, and both variables are set as a captured lane
  # run sets them.
  describe 'the lane capture variables' do
    let(:home) { File.join(tmpdir, 'home') }
    let(:captured) { File.join(tmpdir, 'captured.log') }
    let(:resolver) { Onetime::Utils::ConfigResolver }
    let(:test_yaml) { File.join(home, 'spec', 'logging.test.yaml') }
    let(:etc_yaml) { File.join(home, 'etc', 'logging.yaml') }

    before do
      defaults = File.join(repo_root, 'etc', 'defaults', 'logging.defaults.yaml')
      FileUtils.mkdir_p([File.join(home, 'etc', 'defaults'), File.join(home, 'spec')])
      FileUtils.cp(defaults, File.join(home, 'etc', 'defaults', 'logging.defaults.yaml'))
      FileUtils.cp(defaults, etc_yaml)
      FileUtils.cp(File.join(repo_root, 'spec', 'logging.test.yaml'), test_yaml)
      stub_const('Onetime::HOME', home)

      ENV['LANES_APP_LOG_CONSOLE'] = 'off'
      ENV['LANES_APP_LOG_FILE']    = captured
    end

    def rack_env(value)
      value.nil? ? ENV.delete('RACK_ENV') : ENV['RACK_ENV'] = value
    end

    def loaded_destinations
      instance.send(:load_logging_config).fetch('destinations')
    end

    # The control: the same fixture does turn the console off and the file
    # on under RACK_ENV=test, so the examples below are not passing on a
    # fixture that could never bite.
    it 'turn the console off and the file on under RACK_ENV=test' do
      rack_env('test')

      expect(resolver.resolve('logging')).to eq(test_yaml)
      expect(loaded_destinations).to include(
        'console' => include('enabled' => false),
        'file' => include('enabled' => true, 'path' => captured),
      )
    end

    [nil, '', 'production', 'development', 'staging', 'testing', 'TEST', ' test'].each do |value|
      context "with RACK_ENV=#{value.inspect}" do
        before { rack_env(value) }

        it 'resolve etc/logging.yaml, not the test file beside it' do
          expect(resolver.resolve('logging')).to eq(etc_yaml)
        end

        it 'resolve nothing, not the test file, when etc/logging.yaml is absent' do
          FileUtils.rm(etc_yaml)

          expect(resolver.resolve('logging')).to be_nil
        end

        it 'leave the console on and the file off' do
          expect(loaded_destinations).to eq(shipped_defaults.fetch('destinations'))
          expect(loaded_destinations).to include('console' => include('enabled' => true), 'file' => include('enabled' => false))

          instance.install_destinations
          SemanticLogger['SetupLoggersSafeguardsSpec'].error('an error')

          expect(registry.keys).to eq([:console])
          expect(file_sinks).to be_empty
          expect(File.exist?(captured)).to be(false)
          expect(console_log).to include('an error')
        end
      end
    end
  end
end
