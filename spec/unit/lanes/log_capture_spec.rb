# spec/unit/lanes/log_capture_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# The test-process side of the lane log capture profile (#4683): what
# `tests/lanes/run --capture-logs` and `--log-console` do to a test process
# once the runner has exported their variables.
#
#   LANES_APP_LOG_FILE     application log events are appended to this file
#   LANES_APP_LOG_CONSOLE  off, or a console threshold
#   LANES_MAIL_LOG_FILE    logger-backend emails are appended to this file
#
# Two paths lead from those names to appenders, and both are covered here:
#
#   - A process that boots reads spec/logging.test.yaml, which maps the first
#     two onto the logging config's `destinations` block.
#   - A process that never boots gets the file from Lanes::LogCapture, which
#     spec/spec_helper.rb and try/support/test_helpers.rb call on load.
#
# This spec may itself run under the profile. Every example therefore starts
# from an empty appender list and a cleared set of the variables, and passes
# the values it means to test.
RSpec.describe 'lane log capture profile' do
  include_context 'with isolated log appenders'

  let(:tmpdir) { Dir.mktmpdir('lane_log_capture_spec') }
  let(:app_log) { File.join(tmpdir, 'app.log') }
  let(:mail_log) { File.join(tmpdir, 'mail.log') }
  let(:console_io) { StringIO.new }
  let(:setup_loggers) { Onetime::Initializers::SetupLoggers }
  let(:registry) { setup_loggers.owned_appenders }
  let(:mail_backend) { Onetime::Mail::Delivery::Logger }

  # The names the profile reads, and the two a run must not need: the
  # profile sets no category floor, so LOG_LEVEL and DEBUG_LOGGERS are
  # absent in every example.
  let(:cleared_env) do
    {
      'LANES_APP_LOG_FILE' => nil,
      'LANES_APP_LOG_CONSOLE' => nil,
      'LANES_MAIL_LOG_FILE' => nil,
      'LOG_LEVEL' => nil,
      'DEBUG_LOGGERS' => nil,
    }
  end

  # The mail backend's output is process-wide: give each example the
  # default, close whatever file it opened, and put back what the run had.
  around do |example|
    mail_backend.with_output(nil) do
      example.run
    ensure
      output = mail_backend.output
      output.close if output.is_a?(File) && !output.closed?
    end
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def with_lane_env(env = {}, &)
    ClimateControl.modify(cleared_env.merge(env), &)
  end

  # The logging config a boot loads under +env+: the shipped defaults with
  # spec/logging.test.yaml merged over them.
  def logging_config(env = {})
    with_lane_env(env) { setup_loggers.new.send(:load_logging_config) }
  end

  # What a boot does about destinations under +env+: the resolved logging
  # config, through the initializer. The console device is a StringIO.
  def boot_destinations(env = {})
    initializer = setup_loggers.new
    allow(initializer).to receive(:log_device).and_return(console_io)
    with_lane_env(env) { initializer.install_destinations }
  end

  # SemanticLogger[] returns a new logger each call, so this level is the
  # emitter's own.
  def emitter(level = :trace)
    SemanticLogger['LaneLogCaptureSpec'].tap { |logger| logger.level = level }
  end

  def deliver(subject)
    mail_backend.new({}).perform_delivery(
      to: 'recipient@example.com', from: 'sender@example.com', subject: subject, text_body: 'body',
    )
  end

  def file_sinks
    SemanticLogger.appenders.grep(setup_loggers::FileSink)
  end

  describe 'spec/logging.test.yaml, for a process that boots' do
    let(:shipped_defaults) do
      path = File.join(Onetime::HOME, 'etc', 'defaults', 'logging.defaults.yaml')
      with_lane_env do
        YAML.safe_load(ERB.new(File.read(path)).result, permitted_classes: [Symbol, Date, Time], aliases: true)
      end
    end

    context 'with neither variable set' do
      it 'leaves the destinations at the shipped defaults' do
        expect(logging_config['destinations']).to eq(shipped_defaults['destinations'])
      end

      it 'adds no destinations key to the test config' do
        rendered = with_lane_env { ERB.new(File.read(File.join(Onetime::HOME, 'spec', 'logging.test.yaml'))).result }

        expect(YAML.safe_load(rendered).keys).to eq(%w[default_level formatter loggers http])
      end

      it 'installs the one console appender and no file' do
        boot_destinations

        expect(registry.keys).to eq([:console])
        expect(registry.fetch(:console).identity).to include(stream: :stdout, level: nil, formatter: :default)
        expect(registry.fetch(:console).appender.filter).to be_nil
        expect(SemanticLogger.appenders.size).to eq(1)
      end
    end

    context 'with LANES_APP_LOG_FILE alone' do
      it 'adds the file and leaves the console as it was' do
        boot_destinations('LANES_APP_LOG_FILE' => app_log)

        expect(registry.keys).to eq([:console, :file])
        expect(file_sinks.map(&:file_name)).to eq([app_log])
        expect(registry.fetch(:console).identity).to include(level: nil)
      end

      it 'writes an admitted event to both' do
        boot_destinations('LANES_APP_LOG_FILE' => app_log)

        emitter.error('to the file and the console')

        expect(File.read(app_log)).to include('to the file and the console')
        expect(console_io.string).to include('to the file and the console')
      end

      it 'keeps a path that YAML would otherwise misread' do
        odd_dir = File.join(tmpdir, %(odd: #dir "q" 'x' {y} [z]))
        Dir.mkdir(odd_dir)
        odd_log = File.join(odd_dir, 'app.log')

        boot_destinations('LANES_APP_LOG_FILE' => odd_log)

        expect(file_sinks.map(&:file_name)).to eq([odd_log])
      end
    end

    context 'with LANES_APP_LOG_CONSOLE=off' do
      it 'captures an expected error in the file and keeps it off the console' do
        boot_destinations('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => 'off')

        emitter.error('an expected error')

        expect(registry.keys).to eq([:file])
        expect(SemanticLogger.appenders.to_a).to eq(file_sinks)
        expect(File.read(app_log)).to include('an expected error')
        expect(console_io.string).to be_empty
      end

      it 'stops setup when there is no log file to take the events' do
        expect { boot_destinations('LANES_APP_LOG_CONSOLE' => 'off') }
          .to raise_error(Onetime::ConfigError, /no destination for audit events/)
      end
    end

    context 'with LANES_APP_LOG_CONSOLE set to a level' do
      Lanes::LogCapture::CONSOLE_LEVELS.each do |level|
        it "holds the console to #{level} and leaves the file without a threshold" do
          boot_destinations('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => level)

          expect(registry.fetch(:console).identity).to include(level: level.to_sym)
          expect(registry.fetch(:file).identity).to include(path: app_log, level: nil)
        end
      end

      it 'writes an event below the level to the file alone' do
        boot_destinations('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => 'error')

        emitter.warn('below the console level')
        emitter.error('at the console level')

        expect(File.read(app_log)).to include('below the console level', 'at the console level')
        expect(console_io.string).to include('at the console level')
        expect(console_io.string).not_to include('below the console level')
      end

      it 'applies without a log file' do
        boot_destinations('LANES_APP_LOG_CONSOLE' => 'warn')

        expect(registry.keys).to eq([:console])
        expect(registry.fetch(:console).identity).to include(level: :warn)
      end
    end

    context 'with a LANES_APP_LOG_CONSOLE value that is neither off nor a level' do
      # `false`, `no` and `0` are what a YAML boolean or a shell habit would
      # produce for "off"; none of them may quietly mean it.
      %w[verbose OFF false no 0 warn,error].each do |value|
        it "stops setup for #{value.inspect}" do
          expect { boot_destinations('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => value) }
            .to raise_error(Onetime::ConfigError, /destinations\.console\.level is not a log level/)
          expect(registry).to be_empty
        end
      end
    end

    # The profile routes; it sets no floor. Which events exist is decided by
    # the same category levels with the profile as without it, and neither
    # LOG_LEVEL nor DEBUG_LOGGERS is part of it (both are absent here).
    it 'leaves the default level and every category level as they are without the profile' do
      plain    = logging_config
      profiled = logging_config('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => 'off')

      expect(profiled.except('destinations')).to eq(plain.except('destinations'))
      expect(profiled.fetch('loggers')).to include('Auth' => 'info', 'HTTP' => 'warn')
    end
  end

  describe 'Lanes::LogCapture.install!, for a process that never boots' do
    def install(env = {})
      Lanes::LogCapture.install!(env)
    end

    context 'with none of the variables set' do
      it 'adds no appender and leaves the mail output alone' do
        install

        expect(SemanticLogger.appenders).to be_empty
        expect(registry).to be_empty
        expect(mail_backend.output).to equal($stdout)
      end
    end

    context 'with LANES_APP_LOG_FILE' do
      it 'installs the file and no console' do
        install('LANES_APP_LOG_FILE' => app_log)

        emitter.error('from a spec that never boots')

        expect(registry.keys).to eq([:file])
        expect(SemanticLogger.appenders.to_a).to eq(file_sinks)
        expect(File.read(app_log)).to include('from a spec that never boots')
      end

      it 'appends to what the file already holds' do
        File.write(app_log, "written by an earlier process\n")

        install('LANES_APP_LOG_FILE' => app_log)
        emitter.error('written by this one')

        expect(File.read(app_log).lines.first).to eq("written by an earlier process\n")
        expect(File.read(app_log)).to include('written by this one')
      end

      it 'does not add a second file when called again' do
        2.times { install('LANES_APP_LOG_FILE' => app_log) }

        expect(file_sinks.size).to eq(1)
      end

      it 'leaves the default level alone' do
        expect { install('LANES_APP_LOG_FILE' => app_log) }.not_to(change(SemanticLogger, :default_level))
      end

      # The file this helper installs and the one spec/logging.test.yaml
      # describes must be the same destination, or a boot would replace the
      # appender (and, were the two to differ in path, split the log).
      it 'is the file a later boot keeps, with the console the boot adds' do
        env = { 'LANES_APP_LOG_FILE' => app_log }
        install(env)
        early = registry.fetch(:file).appender

        boot_destinations(env)

        expect(registry.keys).to contain_exactly(:console, :file)
        expect(registry.fetch(:file).appender).to equal(early)
        expect(file_sinks).to eq([early])
      end

      it 'is still the only destination after a boot with the console off' do
        env = { 'LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => 'off' }
        install(env)
        early = registry.fetch(:file).appender

        boot_destinations(env)

        expect(SemanticLogger.appenders.to_a).to eq([early])
      end

      it 'accepts every console value the runner can export' do
        [nil, 'off', *Lanes::LogCapture::CONSOLE_LEVELS].each do |console|
          expect { install('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => console) }.not_to raise_error
        end
      end
    end

    # A write that fails after the file was opened raises nothing in the
    # application. The profile records it beside the log, where the runner
    # looks at the end of the run (spec/unit/lanes/capture_logs_spec.rb).
    context 'with LANES_APP_LOG_FILE, when a write to the file fails' do
      let(:listeners) { setup_loggers::FileSink.write_failure_listeners }
      let(:marker) { "#{app_log}#{Lanes::LogCapture::WRITE_FAILED_SUFFIX}" }

      # The handle is replaced by one whose write raises; reopen does
      # nothing, so the stock appender's one retry fails the same way.
      def fail_write(sink, error)
        broken = Object.new
        broken.define_singleton_method(:write) { |*| raise error }
        broken.define_singleton_method(:close) { nil }
        sink.instance_variable_set(:@file, broken)
        allow(sink).to receive(:reopen)

        # The sink's own line on standard error (once per process) is kept
        # off this run's console.
        event = SemanticLogger::Log.new('LaneLogCaptureSpec', :error).tap { |log| log.assign(message: 'lost') }
        was   = $stderr
        begin
          $stderr = StringIO.new
          expect { sink.log(event) }.to raise_error(error.class)
        ensure
          $stderr = was
        end
      end

      it 'watches the file with one listener, however often it is installed' do
        2.times { install('LANES_APP_LOG_FILE' => app_log) }

        expect(listeners.map(&:class)).to eq([Lanes::LogCapture::WriteFailureMarker])
        expect(listeners.first.app_log).to eq(app_log)
        expect(File.exist?(marker)).to be(false)
      end

      it 'watches the new file when the path changes' do
        other = File.join(tmpdir, 'other.log')
        install('LANES_APP_LOG_FILE' => app_log)
        install('LANES_APP_LOG_FILE' => other)

        expect(listeners.map(&:app_log)).to eq([other])
      end

      it 'leaves the listeners alone without the variable' do
        install('LANES_MAIL_LOG_FILE' => mail_log)

        expect(listeners).to be_empty
      end

      it 'records each failed write in <app log>.write-failed' do
        install('LANES_APP_LOG_FILE' => app_log)
        sink = registry.fetch(:file).appender

        fail_write(sink, Errno::ENOSPC.new('probe'))
        fail_write(sink, IOError.new('closed stream'))

        expect(File.read(marker).lines).to match(
          [
            /\Apid #{Process.pid}: Errno::ENOSPC: .*probe/,
            /\Apid #{Process.pid}: IOError: closed stream/,
          ],
        )
      end

      it 'records nothing for another log file' do
        install('LANES_APP_LOG_FILE' => app_log)
        other = setup_loggers::FileSink.new(File.join(tmpdir, 'other.log'), append: true)
        other.reopen

        fail_write(other, Errno::ENOSPC.new('probe'))

        expect(File.exist?(marker)).to be(false)
      ensure
        other&.close
      end

      it 'leaves the write error as it was when the marker cannot be written' do
        install('LANES_APP_LOG_FILE' => app_log)
        sink = registry.fetch(:file).appender
        FileUtils.mkdir_p(marker) # a directory where the marker would go

        fail_write(sink, Errno::ENOSPC.new('probe'))

        expect(File.directory?(marker)).to be(true)
      end
    end

    context 'with a setting that cannot be honored' do
      it 'refuses a console value that is neither off nor a level' do
        %w[verbose OFF false 0].each do |value|
          expect { install('LANES_APP_LOG_FILE' => app_log, 'LANES_APP_LOG_CONSOLE' => value) }
            .to raise_error(Lanes::LogCapture::Error, /LANES_APP_LOG_CONSOLE must be off or one of trace, debug/)
        end
        expect(SemanticLogger.appenders).to be_empty
      end

      it 'refuses the console off without a log file' do
        expect { install('LANES_APP_LOG_CONSOLE' => 'off') }
          .to raise_error(Lanes::LogCapture::Error, /LANES_APP_LOG_CONSOLE=off needs LANES_APP_LOG_FILE/)
      end

      it 'refuses a relative path' do
        expect { install('LANES_APP_LOG_FILE' => 'tmp/app.log') }
          .to raise_error(Lanes::LogCapture::Error, /LANES_APP_LOG_FILE must be an absolute path/)
        expect { install('LANES_MAIL_LOG_FILE' => 'tmp/mail.log') }
          .to raise_error(Lanes::LogCapture::Error, /LANES_MAIL_LOG_FILE must be an absolute path/)
      end

      it 'names the variable and the path of a log file it cannot open' do
        missing = File.join(tmpdir, 'no-such-directory', 'app.log')

        expect { install('LANES_APP_LOG_FILE' => missing) }
          .to raise_error(Lanes::LogCapture::Error, /LANES_APP_LOG_FILE: Cannot open the log file #{Regexp.escape(missing)}/)
        expect(SemanticLogger.appenders).to be_empty
      end

      it 'names the variable and the path of a mail file it cannot open' do
        missing = File.join(tmpdir, 'no-such-directory', 'mail.log')

        expect { install('LANES_MAIL_LOG_FILE' => missing) }
          .to raise_error(Lanes::LogCapture::Error, /LANES_MAIL_LOG_FILE: cannot open the mail log #{Regexp.escape(missing)}/)
        expect(mail_backend.output).to equal($stdout)
      end
    end

    context 'with LANES_MAIL_LOG_FILE' do
      it 'appends delivered emails to the file instead of printing them' do
        File.write(mail_log, "written by an earlier process\n")
        install('LANES_MAIL_LOG_FILE' => mail_log)

        expect { deliver('to the mail file') }.not_to output.to_stdout

        expect(File.read(mail_log).lines.first).to eq("written by an earlier process\n")
        expect(File.read(mail_log)).to include('=== EMAIL (Logger) ===', 'Subject: to the mail file')
      end

      it 'writes each delivery through, without buffering' do
        install('LANES_MAIL_LOG_FILE' => mail_log)

        expect(mail_backend.output).to be_a(File).and have_attributes(path: mail_log, sync: true)
      end

      it 'keeps the handle it opened when called again' do
        install('LANES_MAIL_LOG_FILE' => mail_log)
        first = mail_backend.output

        install('LANES_MAIL_LOG_FILE' => mail_log)

        expect(mail_backend.output).to equal(first)
      end

      it 'does not install an application log' do
        install('LANES_MAIL_LOG_FILE' => mail_log)

        expect(SemanticLogger.appenders).to be_empty
      end

      it 'keeps the emails out of the application log' do
        install('LANES_APP_LOG_FILE' => app_log, 'LANES_MAIL_LOG_FILE' => mail_log)

        deliver('kept apart')

        expect(File.read(app_log)).not_to include('kept apart')
      end
    end

    context 'without LANES_MAIL_LOG_FILE' do
      it 'prints delivered emails to standard out, as before' do
        install('LANES_APP_LOG_FILE' => app_log)

        expect { deliver('to standard out') }.to output(/Subject: to standard out/).to_stdout
      end
    end

    # The suite logs synchronously (semantic_logger/sync) and its forking
    # specs do not all reopen appenders in the child. The child here writes
    # through the handles it inherited.
    it 'lets a forked child append to both files alongside the parent', skip: !Process.respond_to?(:fork) do
      install('LANES_APP_LOG_FILE' => app_log, 'LANES_MAIL_LOG_FILE' => mail_log)
      expect(SemanticLogger).to be_sync

      emitter.error('parent before the fork')
      deliver('parent before the fork')
      pid = fork do
        status = 1
        emitter.error('child after the fork')
        deliver('child after the fork')
        status = 0
      ensure
        exit!(status) # never run the suite's at_exit hooks in the child
      end
      _, status = Process.wait2(pid)
      emitter.error('parent after the fork')
      deliver('parent after the fork')

      expect(status).to be_success
      expect(File.read(app_log).lines.map { |line| line[/(parent|child) \w+ the fork/] })
        .to eq(['parent before the fork', 'child after the fork', 'parent after the fork'])
      expect(File.read(mail_log).scan(/Subject: (.+)/).flatten)
        .to eq(['parent before the fork', 'child after the fork', 'parent after the fork'])
    end
  end

  describe 'Lanes::LogCapture.install_or_abort!' do
    it 'ends the process with one line on standard error' do
      missing = File.join(tmpdir, 'no-such-directory', 'app.log')

      expect { Lanes::LogCapture.install_or_abort!('LANES_APP_LOG_FILE' => missing) }
        .to raise_error(SystemExit) { |exit| expect(exit.status).to eq(1) }
        .and output(/\Aerror: test log capture: LANES_APP_LOG_FILE: Cannot open the log file #{Regexp.escape(missing)}.*\n\z/).to_stderr
    end

    it 'returns when there is nothing to refuse' do
      expect { Lanes::LogCapture.install_or_abort!({}) }.not_to raise_error
    end
  end

  # The two helper files, each loaded in a process of its own that never
  # boots the application. The parent's lane environment is inherited, minus
  # anything that would let the run's own logging settings stand in for the
  # profile's.
  describe 'the test helpers, loaded in their own process' do
    let(:probe) do
      <<~RUBY
        SemanticLogger['LaneLogCaptureProbe'].error('probe: an expected error')
        Onetime::Mail::Delivery::Logger.new({}).perform_delivery(
          to: 'recipient@example.com', from: 'sender@example.com', subject: 'probe: an email', text_body: 'body',
        )
        puts "probe: appenders=\#{SemanticLogger.appenders.map { |appender| appender.class.name }.join(',')}"
        puts "probe: booted=\#{Onetime.ready?}"
      RUBY
    end

    # `-I lib` is what the tryouts command adds before it loads a file;
    # spec_helper adds it itself.
    def run_helper(helper, env)
      Open3.capture3(
        cleared_env.merge('COVERAGE' => nil, 'LANES_RSPEC_STATUS_FILE' => nil).merge(env),
        RbConfig.ruby, '-I', File.join(Onetime::HOME, 'lib'),
        '-e', "require #{File.join(Onetime::HOME, helper).inspect}\n#{probe}",
        chdir: Onetime::HOME
      )
    end

    {
      'spec/spec_helper.rb' => 'a spec',
      'try/support/test_helpers.rb' => 'a tryout',
    }.each do |helper, kind|
      it "captures the log and the mail of #{kind} that never boots (#{helper})" do
        stdout, stderr, status = run_helper(
          helper,
          'LANES_APP_LOG_FILE' => app_log, 'LANES_MAIL_LOG_FILE' => mail_log, 'LANES_APP_LOG_CONSOLE' => 'off',
        )

        expect(status).to be_success, stderr
        expect(stdout).to include('probe: booted=false')
        expect(stdout).to include('probe: appenders=Onetime::Initializers::SetupLoggers::FileSink')
        expect(File.read(app_log)).to include('probe: an expected error')
        expect(File.read(mail_log)).to include('Subject: probe: an email')
        expect(stdout + stderr).not_to include('probe: an expected error')
        expect(stdout + stderr).not_to include('probe: an email')
      end
    end

    it 'stops spec/spec_helper.rb at load when the log file cannot be opened' do
      missing = File.join(tmpdir, 'no-such-directory', 'app.log')

      stdout, stderr, status = run_helper('spec/spec_helper.rb', 'LANES_APP_LOG_FILE' => missing)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("error: test log capture: LANES_APP_LOG_FILE: Cannot open the log file #{missing}")
      expect(stdout).not_to include('probe:')
    end
  end
end
