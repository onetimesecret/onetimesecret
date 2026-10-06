# spec/unit/onetime/initializers/setup_loggers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# rubocop:disable RSpec/SpecFilePathFormat
# File name matches implementation file setup_loggers.rb
RSpec.describe Onetime::Initializers::SetupLoggers do
  # These tests use mocks to avoid requiring full SemanticLogger configuration

  let(:instance) { described_class.new }

  describe '#cleanup' do
    context 'when SemanticLogger is defined' do
      before do
        stub_const('SemanticLogger', Class.new) unless defined?(SemanticLogger)
        allow(SemanticLogger).to receive(:flush)
      end

      it 'calls SemanticLogger.flush' do
        instance.cleanup
        expect(SemanticLogger).to have_received(:flush)
      end

      it 'does not raise on success' do
        expect { instance.cleanup }.not_to raise_error
      end

      context 'when flush raises an error' do
        before do
          allow(SemanticLogger).to receive(:flush)
            .and_raise(StandardError.new('Flush failed'))
        end

        it 'does not raise error' do
          expect { instance.cleanup }.not_to raise_error
        end

        it 'logs warning to stderr' do
          expect { instance.cleanup }.to output(/SetupLoggers.*Error during cleanup.*Flush failed/).to_stderr
        end

        it 'is idempotent' do
          expect { instance.cleanup }.not_to raise_error
          expect { instance.cleanup }.not_to raise_error
        end
      end
    end

    context 'when SemanticLogger is not defined' do
      before do
        hide_const('SemanticLogger') if defined?(SemanticLogger)
      end

      it 'does not raise error' do
        expect { instance.cleanup }.not_to raise_error
      end

      it 'handles gracefully' do
        # Should complete without attempting to call undefined constant
        instance.cleanup
        # Test passes if no NameError is raised
      end
    end
  end

  describe '#reconnect' do
    context 'when SemanticLogger is defined' do
      before do
        stub_const('SemanticLogger', Class.new) unless defined?(SemanticLogger)
        allow(SemanticLogger).to receive(:reopen)
      end

      it 'calls SemanticLogger.reopen' do
        instance.reconnect
        expect(SemanticLogger).to have_received(:reopen)
      end

      it 'does not raise on success' do
        expect { instance.reconnect }.not_to raise_error
      end

      context 'when reopen raises an error' do
        before do
          allow(SemanticLogger).to receive(:reopen)
            .and_raise(StandardError.new('Reopen failed'))
        end

        it 'does not raise error' do
          expect { instance.reconnect }.not_to raise_error
        end

        it 'logs warning to stderr' do
          expect { instance.reconnect }.to output(/SetupLoggers.*Error during reconnect.*Reopen failed/).to_stderr
        end

        it 'is idempotent' do
          expect { instance.reconnect }.not_to raise_error
          expect { instance.reconnect }.not_to raise_error
        end
      end
    end

    context 'when SemanticLogger is not defined' do
      before do
        hide_const('SemanticLogger') if defined?(SemanticLogger)
      end

      it 'does not raise error' do
        expect { instance.reconnect }.not_to raise_error
      end

      it 'handles gracefully' do
        # Should complete without attempting to call undefined constant
        instance.reconnect
        # Test passes if no NameError is raised
      end
    end
  end

  # #4334 — the OPTIONAL second destination for the operator audit sink. Every
  # ColonelAuditEvent already rides the console appender (stdout); this ships a
  # copy to syslog for operators who want the audit stream separated from
  # application logs. Default OFF, and never allowed to break boot.
  describe '#configure_audit_syslog_appender' do
    before { allow(SemanticLogger).to receive(:add_appender) }

    def configure(settings)
      instance.send(:configure_audit_syslog_appender, { 'audit' => { 'syslog' => settings } })
    end

    it 'does nothing when the config section is absent' do
      instance.send(:configure_audit_syslog_appender, {})

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    it 'is DEFAULT OFF: an unset or false enabled flag adds no appender' do
      configure({})
      configure('enabled' => false)
      configure('enabled' => 'no')

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    it 'adds a syslog appender FILTERED to the audit category when enabled' do
      configure('enabled' => true, 'url' => 'tcp://loghost:514', 'level' => 'info', 'facility' => 'local3')

      expect(SemanticLogger).to have_received(:add_appender).once.with(
        hash_including(
          appender: :syslog,
          url: 'tcp://loghost:514',
          level: :info,
          facility: ::Syslog::LOG_LOCAL3,
        ),
      )
    end

    # A loose filter would quietly start copying unrelated categories into the
    # operator's audit destination.
    it 'filters on the audit category name EXACTLY' do
      configure('enabled' => true)

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(filter: /\AColonelAudit\z/))
    end

    # The appender's own level_map DEFAULT autoloads a formatter that requires
    # the third-party syslog_protocol gem — even for local syslog. Supplying the
    # map explicitly is what keeps the local path dependency-free.
    it 'supplies the level map explicitly so the local path needs no extra gem' do
      configure('enabled' => true)

      expect(SemanticLogger).to have_received(:add_appender).with(
        hash_including(level_map: hash_including(info: ::Syslog::LOG_NOTICE, error: ::Syslog::LOG_ERR)),
      )
    end

    it 'defaults the URL to the local syslog daemon (no third-party gem)' do
      configure('enabled' => true, 'url' => '')

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(url: 'syslog://localhost'))
    end

    it 'falls back to LOG_USER for an unrecognised facility rather than raising' do
      configure('enabled' => true, 'facility' => 'not-a-facility')

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(facility: ::Syslog::LOG_USER))
    end

    it 'is idempotent: a second pass does not stack a duplicate appender' do
      # allocate, not instance_double: the guard matches on the CLASS NAME (the
      # constant only exists once add_appender has loaded the appender file), and
      # a verifying double's class name is RSpec's, not the appender's.
      allow(SemanticLogger).to receive(:appenders)
        .and_return([SemanticLogger::Appender::Syslog.allocate])

      configure('enabled' => true)

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    # An optional log destination must never cost the process its boot: the
    # audit stream still reaches stdout, so only the second copy is lost.
    it 'warns instead of raising when the appender cannot be built' do
      # The real shape of this: a tcp:// or udp:// URL, which ships to a REMOTE
      # syslog server and needs the syslog_protocol gem this repo does not
      # bundle.
      allow(SemanticLogger).to receive(:add_appender).and_raise(LoadError, 'syslog_protocol missing')

      expect { configure('enabled' => true, 'url' => 'udp://loghost:514') }
        .to output(/SetupLoggers.*audit syslog appender not enabled.*syslog_protocol missing/).to_stderr
    end
  end

  # The global URI scrub (Onetime::LogScrubber) is an on_log subscriber. It
  # must be in place before the first appender, and re-running the
  # initializer must not stack a second copy.
  describe '#execute log scrubber registration' do
    let(:scrubber) { Onetime::LogScrubber }
    let(:appender_steps) { %i[configure_console_appender configure_file_appender configure_audit_syslog_appender] }

    around do |example|
      was_registered = scrubber.registered?
      SemanticLogger::Logger.subscribers&.delete(scrubber)
      example.run
    ensure
      SemanticLogger::Logger.subscribers&.delete(scrubber)
      scrubber.register! if was_registered
    end

    before do
      # Everything with process-wide side effects is stubbed; only the
      # registration and the order of the steps are real.
      allow(instance).to receive_messages(load_logging_config: {}, create_cached_loggers: {})
      %i[configure_default_level configure_console_appender configure_file_appender
         configure_audit_syslog_appender ensure_audit_destination!
         apply_env_overrides configure_external_loggers].each { |step| allow(instance).to receive(step) }
      allow(Onetime).to receive(:logging_conf=)
      allow(Onetime::Runtime).to receive(:update_infrastructure)
    end

    it 'registers the scrubber before any appender is added' do
      registered_at = {}
      appender_steps.each do |step|
        allow(instance).to receive(step) { registered_at[step] = scrubber.registered? }
      end

      instance.execute(nil)

      expect(registered_at).to eq(appender_steps.to_h { |step| [step, true] })
    end

    # The same holds for a process that installs the destinations without
    # running the initializer, as a spec helper does.
    it 'registers the scrubber when only the destinations are installed' do
      registered_at = {}
      appender_steps.each do |step|
        allow(instance).to receive(step) { registered_at[step] = scrubber.registered? }
      end

      instance.install_destinations({})

      expect(registered_at).to eq(appender_steps.to_h { |step| [step, true] })
    end

    it 'registers once when the initializer runs twice' do
      2.times { instance.execute(nil) }

      expect(SemanticLogger::Logger.subscribers.count { |s| s.equal?(scrubber) }).to eq(1)
    end
  end

  describe '#backtrace_limit' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('BACKTRACE_LINES').and_return(nil)
      allow(ENV).to receive(:fetch).and_call_original
    end

    def with_rack_env(value)
      allow(ENV).to receive(:fetch).with('RACK_ENV', 'production').and_return(value)
    end

    # The default production console has always carried full backtraces: the
    # 3-line production default this method once named compared Onetime.mode
    # to 'production' and never applied. Truncating by default would change
    # what a default deployment prints (#4683 keeps the defaults as they are).
    it 'is unlimited by default in every environment, production included' do
      %w[production development testing staging].each do |env|
        with_rack_env(env)
        expect(instance.send(:backtrace_limit)).to be_nil, env
      end
    end

    it 'takes the limit from BACKTRACE_LINES in every environment' do
      allow(ENV).to receive(:[]).with('BACKTRACE_LINES').and_return('7')

      %w[production development].each do |env|
        with_rack_env(env)
        expect(instance.send(:backtrace_limit)).to eq(7), env
      end
    end
  end

  describe '#create_cached_loggers' do
    let(:repo_root) { File.expand_path('../../../..', __dir__) }

    def configured_logger_names(relative_path)
      yaml = ERB.new(File.read(File.join(repo_root, relative_path))).result
      YAML.safe_load(yaml, permitted_classes: [Symbol, Date, Time], aliases: true).fetch('loggers').keys
    end

    it 'applies the configured level of each category it defines' do
      config = { 'loggers' => { 'Auth' => 'trace', 'HTTP' => 'fatal' } }
      cache  = instance.send(:create_cached_loggers, config)

      expect(cache['Auth'].level).to eq(:trace)
      expect(cache['HTTP'].level).to eq(:fatal)
    end

    it 'gives a defined category the config does not name the default level' do
      cache = instance.send(:create_cached_loggers, { 'loggers' => {} })

      expect(cache.keys).to match_array(described_class.logger_definitions.keys)
      expect(cache['App'].level).to eq(SemanticLogger.default_level)
    end

    # Chores and CLI are listed at info in the shipped config and have never
    # been applied: both run at the default level. Applying them would make a
    # default `bin/ots` command print its info lines on stderr, which is a
    # change to the default output (#4683 leaves the defaults as they are).
    it 'does not apply a level to Chores or CLI, which follow the default level' do
      config = { 'loggers' => { 'Chores' => 'info', 'CLI' => 'info', 'SetupLoggersSpecAdHoc' => 'trace' } }
      cache  = instance.send(:create_cached_loggers, config)

      expect(cache.keys).not_to include('Chores', 'CLI', 'SetupLoggersSpecAdHoc')

      was = SemanticLogger.default_level
      begin
        %i[warn error].each do |default|
          SemanticLogger.default_level = default
          expect(Onetime.get_logger('Chores').level).to eq(default)
          expect(Onetime.get_logger('CLI').level).to eq(default)
        end
      ensure
        SemanticLogger.default_level = was
      end
    end

    it 'gives Chores and CLI no DEBUG_* flag' do
      expect(described_class.logger_definitions.keys).not_to include('Chores', 'CLI')
      expect(described_class.logger_definitions.values).not_to include('DEBUG_CHORES', 'DEBUG_CLI')
    end

    # The gap between the shipped configs and the initializer is exactly the
    # recorded one. A category added to a config without a definition (it
    # would have no level, no DEBUG_* flag and no entry in the lane runner's
    # --quiet floor, which spec/unit/lanes/quiet_log_floor_spec.rb pins to
    # logger_definitions) fails here.
    it 'defines every category the shipped logging configs name, except the recorded ones' do
      %w[etc/defaults/logging.defaults.yaml spec/logging.test.yaml].each do |path|
        undefined = configured_logger_names(path) - described_class.logger_definitions.keys
        expect(undefined - described_class::UNAPPLIED_CONFIG_CATEGORIES).to be_empty, path
      end

      expect(configured_logger_names('etc/defaults/logging.defaults.yaml'))
        .to include(*described_class::UNAPPLIED_CONFIG_CATEGORIES)
    end
  end

  # The console formatter under a backtrace limit (BACKTRACE_LINES):
  # build_formatter wraps the configured formatter in a proc that renders a
  # copy of the event with a shortened exception backtrace.
  describe 'truncating formatter output' do
    let(:secret) { 's3cret' }
    let(:io) { StringIO.new }
    let(:appenders) { [] }

    around do |example|
      was_registered = Onetime::LogScrubber.registered?
      Onetime::LogScrubber.register!
      example.run
    ensure
      appenders.each { |appender| SemanticLogger.remove_appender(appender) }
      SemanticLogger::Logger.subscribers&.delete(Onetime::LogScrubber) unless was_registered
    end

    it 'writes a scrubbed, backtrace-truncated line through the color formatter' do
      allow(instance).to receive(:backtrace_limit).and_return(1)
      formatter = instance.send(:build_formatter, { 'formatter' => 'color' })
      appenders << SemanticLogger.add_appender(io: io, formatter: formatter, level: :trace, filter: /\ASetupLoggersSpec\z/)
      ex        = begin
        raise IOError, "down redis://u:#{secret}@db/0?password=#{secret}"
      rescue IOError => e
        e
      end

      SemanticLogger['SetupLoggersSpec'].tap { |l| l.level = :trace }.error("failed at https://u:#{secret}@h.example/x?t=1", exception: ex)
      SemanticLogger.flush

      expect(formatter).to be_a(Proc)
      expect(io.string).to include('failed at https://***@h.example/x?***', 'down redis://***@db/0?***', 'more lines)')
      expect(io.string).not_to include(secret)
    end

    # SemanticLogger hands one Log to every appender, and the exception is
    # the caller's: it may still be re-raised or reported to Sentry.
    it 'truncates for its own appender only, leaving the exception and later appenders whole' do
      allow(instance).to receive(:backtrace_limit).and_return(1)
      full_io   = StringIO.new
      formatter = instance.send(:build_formatter, { 'formatter' => 'default' })
      appenders << SemanticLogger.add_appender(io: io, formatter: formatter, level: :trace, filter: /\ASetupLoggersSpec\z/)
      appenders << SemanticLogger.add_appender(io: full_io, formatter: :default, level: :trace, filter: /\ASetupLoggersSpec\z/)
      ex        = begin
        raise IOError, 'down'
      rescue IOError => e
        e
      end
      backtrace = ex.backtrace.dup

      SemanticLogger['SetupLoggersSpec'].tap { |l| l.level = :trace }.error('failed', exception: ex)
      SemanticLogger.flush

      expect(backtrace.size).to be > 1
      expect(io.string).to include(backtrace.first, "... (#{backtrace.size - 1} more lines)")
      expect(io.string).not_to include(backtrace.last)
      expect(ex.backtrace).to eq(backtrace)
      expect(full_io.string).to include(*backtrace)
      expect(full_io.string).not_to include('more lines)')
    end
  end

  # The console and file destinations (#4683), end to end: real appenders,
  # real formatters and filters, a real file. Every appender the process
  # already has is set aside for the example and put back afterwards (the
  # shared context), so each example starts from an empty appender list and
  # leaves the suite's own logging as it found it.
  describe 'log destinations' do
    include_context 'with isolated log appenders'

    let(:tmpdir) { Dir.mktmpdir('setup_loggers_spec') }
    let(:log_path) { File.join(tmpdir, 'app.log') }
    let(:console_io) { StringIO.new }
    let(:unrelated_io) { StringIO.new }
    let(:registry) { described_class.owned_appenders }
    let(:secret) { 's3cret' }
    let(:shipped_defaults) do
      path = File.expand_path('../../../../etc/defaults/logging.defaults.yaml', __dir__)
      YAML.safe_load(ERB.new(File.read(path)).result, permitted_classes: [Symbol, Date, Time], aliases: true)
    end

    after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

    # The console device is a StringIO unless an example asks for the real one.
    before { allow(instance).to receive(:log_device).and_return(console_io) }

    def config(console: {}, file: nil, audit_syslog: false)
      {
        'formatter' => 'default',
        'destinations' => {
          'console' => console,
          'file' => file ? { 'enabled' => true, 'path' => log_path }.merge(file) : { 'enabled' => false },
        },
        'audit' => { 'syslog' => { 'enabled' => audit_syslog } },
      }
    end

    def install(**)
      instance.install_destinations(config(**))
    end

    # SemanticLogger[] returns a new logger each call, so the level set here
    # is this emitter's category level and nobody else's.
    def emitter(level = :trace, name: 'SetupLoggersSpec')
      SemanticLogger[name].tap { |logger| logger.level = level }
    end

    def audit_emitter
      emitter(:info, name: described_class::AUDIT_SINK_LOGGER_NAME)
    end

    def file_log(path = log_path)
      File.read(path)
    end

    def console_log
      console_io.string
    end

    def file_sinks
      SemanticLogger.appenders.grep(described_class::FileSink)
    end

    def add_unrelated_appender
      SemanticLogger.add_appender(io: unrelated_io, formatter: :default, level: :trace, filter: /\ASetupLoggersSpec\z/)
    end

    def use_real_console(cli:)
      allow(instance).to receive(:log_device).and_call_original
      allow(Onetime).to receive(:mode?).and_call_original
      allow(Onetime).to receive(:mode?).with(:cli).and_return(cli)
    end

    def stub_syslog
      require 'syslog'
      lines = []
      allow(Syslog).to receive(:opened?).and_return(false)
      allow(Syslog).to receive(:open)
      allow(Syslog).to receive(:log) { |_priority, line| lines << line }
      lines
    end

    def raised_error
      raise IOError, 'down'
    rescue IOError => ex
      ex
    end

    describe 'the shipped defaults' do
      it 'add the one console appender on stdout in server modes, as before' do
        use_real_console(cli: false)

        expect do
          expect do
            instance.install_destinations(shipped_defaults)
            emitter.warn('to the console')
          end.to output(/to the console/).to_stdout
        end.not_to output.to_stderr

        appender = SemanticLogger.appenders.first
        expect(SemanticLogger.appenders.size).to eq(1)
        expect(appender).to be_an_instance_of(SemanticLogger::Appender::IO)
        expect([appender.level, appender.filter]).to eq([:trace, nil])
        expect(appender.formatter)
          .to be_an_instance_of(SemanticLogger::Formatters.factory(shipped_defaults['formatter'].to_sym).class)
      end

      it 'add the one console appender on stderr under the CLI, as before' do
        use_real_console(cli: true)

        expect do
          expect do
            instance.install_destinations(shipped_defaults)
            emitter.warn('to the console')
          end.to output(/to the console/).to_stderr
        end.not_to output.to_stdout

        appender = SemanticLogger.appenders.first
        expect(SemanticLogger.appenders.size).to eq(1)
        expect(appender).to be_an_instance_of(SemanticLogger::Appender::IO)
        expect([appender.level, appender.filter]).to eq([:trace, nil])
        expect(appender.formatter).to be_an_instance_of(SemanticLogger::Formatters::Color)
      end

      it 'leave the file destination off' do
        expect(shipped_defaults.dig('destinations', 'file')).to include('enabled' => false, 'path' => nil)

        instance.install_destinations(shipped_defaults)

        expect(file_sinks).to be_empty
        expect(registry.keys).to eq([:console])
      end

      it 'behave exactly as a config without a destinations block' do
        instance.install_destinations(shipped_defaults.except('destinations'))

        expect(registry.fetch(:console).identity)
          .to eq(instance.send(:console_destination, shipped_defaults))
        expect(registry.keys).to eq([:console])
      end
    end

    # The formatter selection that predates the destinations block: the
    # top-level `formatter` in server modes, color under the CLI, and the
    # backtrace-truncating wrapper when a limit applies.
    describe 'console formatter selection' do
      def console_formatter(settings, cli:)
        use_real_console(cli: cli)
        expect { instance.install_destinations(settings) }.not_to output.to_stdout
        registry.fetch(:console).appender.formatter
      end

      it 'uses the top-level formatter in server modes' do
        expect(console_formatter({ 'formatter' => 'json' }, cli: false)).to be_an_instance_of(SemanticLogger::Formatters::Json)
      end

      it 'defaults to color in server modes' do
        expect(console_formatter({}, cli: false)).to be_an_instance_of(SemanticLogger::Formatters::Color)
      end

      it 'uses color under the CLI whatever the top-level formatter says' do
        expect(console_formatter({ 'formatter' => 'json' }, cli: true)).to be_an_instance_of(SemanticLogger::Formatters::Color)
      end

      it 'wraps the formatter when a backtrace limit applies' do
        allow(instance).to receive(:backtrace_limit).and_return(3)

        expect(console_formatter({ 'formatter' => 'json' }, cli: false)).to be_a(Proc)
      end

      it 'uses destinations.console.formatter in every mode when it is set' do
        settings = { 'formatter' => 'color', 'destinations' => { 'console' => { 'formatter' => 'json' } } }

        expect(console_formatter(settings, cli: true)).to be_an_instance_of(SemanticLogger::Formatters::Json)
      end
    end

    describe 'destination thresholds' do
      it 'writes an event its category admits to the file while the console threshold rejects it' do
        install(console: { 'level' => 'warn' }, file: {})

        emitter(:info).info('routine detail')
        emitter(:info).warn('needs attention')

        expect(file_log).to include('routine detail', 'needs attention')
        expect(console_log).to include('needs attention')
        expect(console_log).not_to include('routine detail')
      end

      it 'applies the file threshold independently of the console' do
        install(file: { 'level' => 'error' })

        emitter.warn('needs attention')
        emitter.error('broke')

        expect(console_log).to include('needs attention', 'broke')
        expect(file_log).to include('broke')
        expect(file_log).not_to include('needs attention')
      end

      # Category levels decide what is generated. A destination only filters
      # what was generated.
      it 'cannot recover an event the category rejected' do
        install(console: { 'level' => 'trace' }, file: { 'level' => 'trace' })

        emitter(:warn).info('never generated')

        expect(file_log).to be_empty
        expect(console_log).to be_empty
      end

      it 'accepts a level in any case and with surrounding space' do
        install(console: { 'level' => ' WARN ' })

        emitter.info('routine detail')
        emitter.warn('needs attention')

        expect(console_log).to include('needs attention')
        expect(console_log).not_to include('routine detail')
      end

      it 'writes plain text to the file unless a formatter is set' do
        install(file: {})
        expect(file_sinks.first.formatter).to be_an_instance_of(SemanticLogger::Formatters::Default)

        install(file: { 'formatter' => 'json' })
        expect(file_sinks.first.formatter).to be_an_instance_of(SemanticLogger::Formatters::Json)
      end
    end

    describe 'with the console disabled and the file enabled' do
      it 'captures an error in the file and writes nothing to the console' do
        use_real_console(cli: false)

        expect do
          expect do
            install(console: { 'enabled' => false }, file: {})
            emitter.error('expected failure')
          end.not_to output.to_stdout
        end.not_to output.to_stderr

        expect(SemanticLogger.appenders.to_a).to eq(file_sinks)
        expect(file_log).to include('expected failure')
      end

      it 'removes a console appender an earlier run added' do
        install(file: {})
        install(console: { 'enabled' => false }, file: {})

        emitter.error('expected failure')

        expect(registry.keys).to eq([:file])
        expect(console_log).to be_empty
        expect(file_log).to include('expected failure')
      end
    end

    # ColonelAudit emits at info and is the durable copy of each audit
    # event. A destination threshold never drops it, and a configuration
    # with nowhere to write it does not start.
    describe 'audit events' do
      it 'ride the console by default, as in production' do
        use_real_console(cli: false)

        expect do
          instance.install_destinations(shipped_defaults)
          audit_emitter.info('operator action')
        end.to output(/ColonelAudit.*operator action/).to_stdout

        expect(SemanticLogger.appenders.size).to eq(1)
      end

      it 'reach the console and the audit syslog appender, which gets nothing else' do
        syslog_lines = stub_syslog
        install(audit_syslog: true)

        audit_emitter.info('operator action')
        emitter.error('application error')

        expect(console_log).to include('operator action', 'application error')
        expect(syslog_lines.size).to eq(1)
        expect(syslog_lines.first).to include('operator action')
      end

      it 'pass a console threshold above their level' do
        install(console: { 'level' => 'error' })

        audit_emitter.info('operator action')
        emitter(:info).info('routine detail')

        expect(console_log).to include('operator action')
        expect(console_log).not_to include('routine detail')
      end

      it 'pass a file threshold above their level' do
        install(console: { 'level' => 'fatal' }, file: { 'level' => 'fatal' })

        audit_emitter.info('operator action')

        expect(file_log).to include('operator action')
        expect(console_log).to include('operator action')
      end

      it 'go to the file when the console is disabled' do
        install(console: { 'enabled' => false }, file: { 'level' => 'error' })

        audit_emitter.info('operator action')

        expect(file_log).to include('operator action')
      end

      it 'go to syslog when the console and the file are both disabled' do
        syslog_lines = stub_syslog
        install(console: { 'enabled' => false }, audit_syslog: true)

        audit_emitter.info('operator action')

        expect(syslog_lines.size).to eq(1)
        expect(syslog_lines.first).to include('operator action')
      end

      it 'refuse a configuration that leaves them no destination' do
        expect { install(console: { 'enabled' => false }) }
          .to raise_error(Onetime::ConfigError, /no destination for audit events/)
      end

      # The syslog appender is optional and its failure is only a warning,
      # which is safe only while another destination exists.
      it 'refuse a configuration whose only destination, syslog, could not be added' do
        allow(SemanticLogger).to receive(:add_appender).and_call_original
        allow(SemanticLogger).to receive(:add_appender)
          .with(hash_including(appender: :syslog)).and_raise(LoadError, 'syslog_protocol missing')

        expect do
          expect { install(console: { 'enabled' => false }, audit_syslog: true) }
            .to raise_error(Onetime::ConfigError, /no destination for audit events/)
        end.to output(/audit syslog appender not enabled/).to_stderr
      end
    end

    describe 'running setup again' do
      it 'adds nothing when the settings are unchanged' do
        unrelated = add_unrelated_appender
        install(console: { 'level' => 'warn' }, file: {})
        appenders = SemanticLogger.appenders.to_a

        install(console: { 'level' => 'warn' }, file: {})
        emitter.warn('once')

        expect(SemanticLogger.appenders.to_a).to eq(appenders)
        expect(appenders).to include(unrelated)
        expect([file_log, console_log, unrelated_io.string].map { |log| log.scan('once').size }).to eq([1, 1, 1])
      end

      # Boot builds a new initializer instance each time; the record of what
      # was added is shared by all of them.
      it 'adds nothing when another initializer instance runs it' do
        install(console: { 'enabled' => false }, file: {})
        sink = registry.fetch(:file).appender

        described_class.new.install_destinations(config(console: { 'enabled' => false }, file: {}))

        expect(SemanticLogger.appenders.to_a).to eq([sink])
      end

      it 'closes the old file and writes to the new one when the path changes' do
        unrelated  = add_unrelated_appender
        other_path = File.join(tmpdir, 'other.log')
        install(file: {})
        old_sink   = registry.fetch(:file).appender
        old_handle = old_sink.instance_variable_get(:@file)
        emitter.warn('before the change')

        install(file: { 'path' => other_path })
        emitter.warn('after the change')

        expect(old_handle).to be_closed
        expect(file_sinks.map(&:file_name)).to eq([other_path])
        expect(file_log).to include('before the change')
        expect(file_log).not_to include('after the change')
        expect(file_log(other_path)).to include('after the change')
        expect(SemanticLogger.appenders.to_a).to include(unrelated)
        expect(unrelated_io.string).to include('before the change', 'after the change')
      end

      it 'replaces the console appender when its threshold changes' do
        unrelated = add_unrelated_appender
        install
        first     = registry.fetch(:console).appender

        install(console: { 'level' => 'error' })
        emitter.warn('needs attention')

        expect(SemanticLogger.appenders.to_a).to contain_exactly(unrelated, registry.fetch(:console).appender)
        expect(registry.fetch(:console).appender).not_to be(first)
        expect(console_log).to be_empty
        expect(unrelated_io.string).to include('needs attention')
      end

      it 'removes and closes the file sink when the file is disabled' do
        install(file: {})
        handle = registry.fetch(:file).appender.instance_variable_get(:@file)

        install
        emitter.warn('console only')

        expect(handle).to be_closed
        expect(file_sinks).to be_empty
        expect(registry.keys).to eq([:console])
        expect(file_log).to be_empty
      end

      it 'keeps the current file sink when the new one cannot be opened' do
        install(file: {})
        sink = registry.fetch(:file).appender

        expect { install(file: { 'path' => File.join(tmpdir, 'missing', 'app.log') }) }
          .to raise_error(Onetime::ConfigError)
        emitter.warn('still captured')

        expect(file_sinks).to eq([sink])
        expect(file_log).to include('still captured')
      end

      it 'adds a fresh appender when the one it added was removed elsewhere' do
        install(file: {})
        SemanticLogger.appenders.to_a.each { |appender| SemanticLogger.remove_appender(appender) }

        install(file: {})
        emitter.warn('after the reset')

        expect(SemanticLogger.appenders.size).to eq(2)
        expect(file_log).to include('after the reset')
        expect(console_log).to include('after the reset')
      end

      # A tryout's `add_appender(io: $stdout)`. SemanticLogger refuses a
      # second console appender, so ours is not requested.
      it 'leaves a console appender someone else added as the console' do
        use_real_console(cli: false)
        allow(SemanticLogger).to receive(:add_appender).and_call_original

        expect do
          foreign = SemanticLogger.add_appender(io: $stdout, formatter: :default)
          instance.install_destinations(shipped_defaults)
          audit_emitter.info('operator action')

          expect(SemanticLogger.appenders.to_a).to eq([foreign])
        end.to output(/operator action/).to_stdout

        expect(SemanticLogger).to have_received(:add_appender).once
        expect(registry).to be_empty
      end
    end

    describe 'a file that cannot be opened' do
      it 'raises at setup, naming the path, when the directory is missing' do
        path = File.join(tmpdir, 'missing', 'app.log')

        expect { install(file: { 'path' => path }) }
          .to raise_error(Onetime::ConfigError, /Cannot open the log file #{Regexp.escape(path)} .*Errno::ENOENT/)
        expect(file_sinks).to be_empty
        expect(registry.keys).to eq([:console])
      end

      it 'raises at setup when the path is a directory' do
        expect { install(file: { 'path' => tmpdir }) }
          .to raise_error(Onetime::ConfigError, /Cannot open the log file #{Regexp.escape(tmpdir)} /)
        expect(file_sinks).to be_empty
      end

      it 'raises at setup when the file is enabled without a path' do
        expect { install(file: { 'path' => ' ' }) }
          .to raise_error(Onetime::ConfigError, /destinations\.file\.path is not set/)
        expect(SemanticLogger.appenders).to be_empty
      end

      it 'resolves a relative path against the application root' do
        expect(instance.send(:file_destination, config(file: { 'path' => 'log/app.log' })))
          .to include(path: File.join(Onetime::HOME, 'log', 'app.log'))
      end

      it 'appends to an existing file instead of truncating it' do
        File.write(log_path, "earlier run\n")

        install(file: {})
        emitter.warn('this run')

        expect(file_log).to start_with("earlier run\n")
        expect(file_log).to include('this run')
      end
    end

    describe 'invalid destination settings' do
      it 'rejects an unknown level without changing any appender' do
        install
        appenders = SemanticLogger.appenders.to_a

        expect { install(console: { 'level' => 'loud' }, file: {}) }
          .to raise_error(Onetime::ConfigError, /destinations\.console\.level is not a log level/)
        expect(SemanticLogger.appenders.to_a).to eq(appenders)
      end

      it 'rejects an unrecognized enabled value' do
        expect { install(file: { 'enabled' => 'maybe' }) }
          .to raise_error(Onetime::ConfigError, /destinations\.file\.enabled/)
      end

      it 'rejects an unknown formatter' do
        expect { install(file: { 'formatter' => 'sparkles' }) }
          .to raise_error(Onetime::ConfigError, /destinations\.file\.formatter is not a known formatter/)
      end
    end

    it 'scrubs the event before it reaches the file' do
      install(file: {})

      emitter.error("failed at https://u:#{secret}@h.example/x?t=1", target: "redis://u:#{secret}@db/0")

      expect(file_log).to include('failed at https://***@h.example/x?***', 'redis://***@db/0')
      expect(file_log).not_to include(secret)
      expect(console_log).not_to include(secret)
    end

    # One Log goes to every appender, and the exception is the caller's.
    it 'writes the full backtrace to the file while the console shortens its own copy' do
      allow(instance).to receive(:backtrace_limit).and_return(1)
      install(file: {})
      exception = raised_error
      backtrace = exception.backtrace.dup

      emitter.error('failed', exception: exception)

      expect(backtrace.size).to be > 1
      expect(console_log).to include(backtrace.first, "... (#{backtrace.size - 1} more lines)")
      expect(console_log).not_to include(backtrace.last)
      expect(file_log).to include(*backtrace)
      expect(file_log).not_to include('more lines)')
      expect(exception.backtrace).to eq(backtrace)
    end

    describe 'process lifecycle' do
      it 'flushes the file sink on cleanup' do
        install(file: {})
        sink = registry.fetch(:file).appender
        allow(sink).to receive(:flush).and_call_original
        emitter.error('before the fork')

        instance.cleanup

        expect(sink).to have_received(:flush)
        expect(file_log).to include('before the fork')
      end

      # reopen is what a forked worker calls. A rotated-away file shows that
      # the sink really holds a new handle on its path afterwards.
      it 'reopens the file sink on reconnect' do
        install(file: {})
        rotated = "#{log_path}.1"
        emitter.error('first handle')
        File.rename(log_path, rotated)

        instance.reconnect
        emitter.error('second handle')

        expect(file_log(rotated)).to include('first handle')
        expect(file_log).to include('second handle')
        expect(file_log).not_to include('first handle')
      end

      it 'appends from a forked child that reconnects, alongside the parent', skip: !Process.respond_to?(:fork) do
        install(console: { 'enabled' => false }, file: {})
        emitter.error('parent before the fork')
        instance.cleanup

        pid = fork do
          status = 1
          instance.reconnect
          emitter.error('child after the fork')
          status = 0
        ensure
          exit!(status) # never run the suite's at_exit hooks in the child
        end
        _, status = Process.wait2(pid)
        emitter.error('parent after the fork')

        expect(status).to be_success
        expect(file_log.lines.size).to eq(3)
        expect(file_log).to include('parent before the fork', 'child after the fork', 'parent after the fork')
      end

      # Production logs asynchronously; this suite does not. A separate
      # process shows that an event still queued at exit reaches the file.
      it 'writes queued events to the file on a normal exit' do
        script = <<~RUBY
          require 'onetime'
          Onetime::Initializers::SetupLoggers.install_destinations(
            'destinations' => {
              'console' => { 'enabled' => false },
              'file' => { 'enabled' => true, 'path' => ARGV.fetch(0) },
            },
          )
          abort 'expected asynchronous logging' if SemanticLogger.sync?
          SemanticLogger['SetupLoggersSpec'].error('queued at exit')
        RUBY

        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', File.join(Onetime::HOME, 'lib'), '-e', script, log_path)

        expect(status).to be_success, stderr
        expect(file_log).to include('queued at exit')
        expect(stdout + stderr).not_to include('queued at exit')
      end
    end

    describe 'FileSink' do
      it 'closes its file, and reopens it when logged to again' do
        install(console: { 'enabled' => false }, file: {})
        sink   = registry.fetch(:file).appender
        handle = sink.instance_variable_get(:@file)

        sink.close
        sink.close
        emitter.error('after close')

        expect(handle).to be_closed
        expect(file_log).to include('after close')
      end

      # A write to the open file that fails. SemanticLogger rescues what an
      # appender raises and prints one "Failed to log to appender" line per
      # event on its internal logger, for any exception at all; the sink
      # reports the I/O errors itself.
      describe 'a write that fails' do
        let(:listener_calls) { [] }

        # The file handle is replaced by one whose write raises. The stock
        # appender retries once after a reopen, which would put a working
        # handle back, so reopen does nothing here. A plain object, not a
        # double: the sink closes it after the example, on removal.
        def failing_sink(error)
          install(console: { 'enabled' => false }, file: {})
          sink   = registry.fetch(:file).appender
          broken = Object.new
          broken.define_singleton_method(:write) { |*| raise error }
          broken.define_singleton_method(:close) { nil }
          sink.instance_variable_set(:@file, broken)
          allow(sink).to receive(:reopen)
          sink
        end

        def event
          SemanticLogger::Log.new('SetupLoggersSpec', :error).tap { |log| log.assign(message: 'an event the file could not take') }
        end

        def listen
          described_class::FileSink.write_failure_listeners << ->(file_name, error) { listener_calls << [file_name, error.class] }
        end

        it 'says so once per process on standard error, naming the file and the error' do
          sink = failing_sink(Errno::ENOSPC.new('probe'))
          prefix = Regexp.escape("#{described_class::FileSink::WRITE_FAILURE_PREFIX} #{log_path}: Errno::ENOSPC: ")
          line   = /\A#{prefix}.*probe.*\n\z/

          expect { expect { sink.log(event) }.to raise_error(Errno::ENOSPC) }.to output(line).to_stderr
          expect { expect { sink.log(event) }.to raise_error(Errno::ENOSPC) }.not_to output.to_stderr
          expect(described_class::FileSink::WRITE_FAILURE_PREFIX).to eq('[SetupLoggers] Cannot write to the log file')
        end

        # A forked child inherits the sink, and with it the parent's record
        # of having reported.
        it 'says so again in another process' do
          sink = failing_sink(Errno::ENOSPC.new('probe'))
          expect { expect { sink.log(event) }.to raise_error(Errno::ENOSPC) }.to output.to_stderr

          allow(Process).to receive(:pid).and_return(Process.pid + 1)

          expect { expect { sink.log(event) }.to raise_error(Errno::ENOSPC) }.to output(/Cannot write to the log file/).to_stderr
        end

        it 'calls each listener with the path and the error, for every failed write' do
          listen
          sink = failing_sink(IOError.new('closed stream'))

          expect do
            2.times { expect { sink.log(event) }.to raise_error(IOError) }
          end.to output.to_stderr

          expect(listener_calls).to eq([[log_path, IOError], [log_path, IOError]])
        end

        # Bunny raises ShutdownSignal (a StandardError) into its reader
        # thread when a session closes, and the thread may be inside an
        # appender at that moment. That is not a failed write.
        it 'does not report an error that is not an I/O error' do
          listen
          interrupted = Class.new(StandardError)
          sink        = failing_sink(interrupted.new('interrupted while logging'))

          expect { expect { sink.log(event) }.to raise_error(interrupted) }.not_to output.to_stderr
          expect(listener_calls).to be_empty
        end

        it 'raises the write error when a listener raises' do
          described_class::FileSink.write_failure_listeners << ->(*) { raise 'listener failed' }
          listen
          sink = failing_sink(Errno::EIO.new('probe'))

          expect { expect { sink.log(event) }.to raise_error(Errno::EIO) }.to output.to_stderr
        end

        it 'reports nothing for a write that succeeds' do
          listen
          install(console: { 'enabled' => false }, file: {})

          expect { emitter.error('written') }.not_to output.to_stderr
          expect(listener_calls).to be_empty
          expect(file_log).to include('written')
        end
      end
    end

    describe '.install_destinations' do
      it 'installs the destinations of the given config' do
        described_class.install_destinations(config(console: { 'enabled' => false }, file: {}))

        emitter.error('through the class method')

        expect(registry.keys).to eq([:file])
        expect(file_log).to include('through the class method')
      end

      it 'loads the logging config files when no config is given' do
        initializer = described_class.new
        allow(described_class).to receive(:new).and_return(initializer)
        allow(initializer).to receive(:load_logging_config)
          .and_return(config(console: { 'enabled' => false }, file: {}))

        described_class.install_destinations

        expect(file_sinks.map(&:file_name)).to eq([log_path])
      end
    end
  end

  # The audit syslog appender exactly as configure_audit_syslog_appender
  # builds it (real appender, real default formatter, real filter), with the
  # libc boundary stubbed: ::Syslog.open and ::Syslog.log are the only calls
  # the appender makes for a syslog:// URL, so capturing ::Syslog.log sees
  # the finished line without writing to the host's syslog.
  describe 'audit syslog appender output' do
    let(:syslog_lines) { [] }
    let(:secret) { 's3cret' }

    around do |example|
      was_registered = Onetime::LogScrubber.registered?
      Onetime::LogScrubber.register!
      example.run
    ensure
      SemanticLogger.appenders.select { |a| a.class.name.to_s.end_with?('Appender::Syslog') }
        .each { |appender| SemanticLogger.remove_appender(appender) }
      SemanticLogger::Logger.subscribers&.delete(Onetime::LogScrubber) unless was_registered
    end

    before do
      require 'syslog'
      allow(Syslog).to receive(:opened?).and_return(false)
      allow(Syslog).to receive(:open)
      allow(Syslog).to receive(:log) { |_priority, line| syslog_lines << line }
    end

    it 'ships the scrubbed audit event' do
      expect(SemanticLogger.appenders.map { |a| a.class.name.to_s }).not_to include(end_with('Appender::Syslog'))
      instance.send(:configure_audit_syslog_appender, { 'audit' => { 'syslog' => { 'enabled' => true } } })

      audit = SemanticLogger[described_class::AUDIT_SINK_LOGGER_NAME].tap { |l| l.level = :trace }
      audit.info("operator action via https://ops:#{secret}@admin.example/run?token=#{secret}", target: "redis://u:#{secret}@db/0")
      SemanticLogger.flush

      expect(syslog_lines.size).to eq(1)
      expect(syslog_lines.first).to include('https://***@admin.example/run?***', 'redis://***@db/0')
      expect(syslog_lines.first).not_to include(secret)
    end
  end
end
