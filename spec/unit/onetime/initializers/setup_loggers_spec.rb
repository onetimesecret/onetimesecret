# spec/unit/onetime/initializers/setup_loggers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

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
      %i[configure_default_level configure_appender configure_audit_syslog_appender
         apply_env_overrides configure_external_loggers].each { |step| allow(instance).to receive(step) }
      allow(Onetime).to receive(:logging_conf=)
      allow(Onetime::Runtime).to receive(:update_infrastructure)
    end

    it 'registers the scrubber before any appender is added' do
      registered_at = {}
      %i[configure_appender configure_audit_syslog_appender].each do |step|
        allow(instance).to receive(step) { registered_at[step] = scrubber.registered? }
      end

      instance.execute(nil)

      expect(registered_at).to eq(configure_appender: true, configure_audit_syslog_appender: true)
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

    # Onetime.mode is the entry point (:app, :cli, :test, ...), never the
    # environment name, so the limit has to come from RACK_ENV.
    it 'limits backtraces to 3 lines in production, whatever the mode' do
      with_rack_env('production')

      expect(Onetime.mode).not_to eq('production')
      expect(instance.send(:backtrace_limit)).to eq(3)
    end

    it 'is unlimited outside production' do
      %w[development testing staging].each do |env|
        with_rack_env(env)
        expect(instance.send(:backtrace_limit)).to be_nil
      end
    end

    it 'lets BACKTRACE_LINES override the environment default' do
      allow(ENV).to receive(:[]).with('BACKTRACE_LINES').and_return('7')

      with_rack_env('production')
      expect(instance.send(:backtrace_limit)).to eq(7)

      with_rack_env('development')
      expect(instance.send(:backtrace_limit)).to eq(7)
    end
  end

  # The production console formatter: build_formatter wraps the configured
  # formatter in a proc that renders a copy of the event with a shortened
  # exception backtrace.
  describe 'production formatter output' do
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
