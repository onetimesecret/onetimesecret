# spec/unit/lanes/capture_logs_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/lane_probe'
require 'shellwords'
require 'tmpdir'

# The files `tests/lanes/run --capture-logs` owns (#4683): app.log and
# mail.log in the run directory, beside last.log.
#
# The test processes only append to them and never create a directory
# (tests/lanes/support/log_capture.rb, spec/logging.test.yaml), so creating,
# truncating, removing and reporting them is the runner's job, and so is
# stopping the run when it cannot. Those are the things pinned here. Which
# names the flags export is hermetic_boundary_spec.rb; the flag grammar is
# argument_handling_spec.rb; what a test process does with the names is
# log_capture_spec.rb.
#
# Every example runs the real runner against the `selftest` lane (no
# services, no application code) under a throwaway overlay, so each has a
# run directory of its own under tmp/lanes/selftest/ and none touches the
# files of a lane a developer is working in. Where a step has to fail, or
# has to show what environment it received, a stub command is put ahead of
# the real one on PATH (LaneProbe.with_fake_commands).
RSpec.describe 'tests/lanes/run --capture-logs files' do
  let(:probe) { LaneProbe }

  include_context 'with the lane runner bash'

  def exit_records(log, code)
    log.lines.grep(/^\[lane:selftest\] log: .* \(exit #{code}\)$/)
  end

  describe 'a run that asks for them' do
    it 'creates both files empty, replacing what the previous run left' do
      probe.with_scratch do |scratch|
        File.binwrite(scratch.app_log, 'previous-run-app-log')
        File.binwrite(scratch.mail_log, 'previous-run-mail-log')

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect(run.exitstatus).to eq(0), run.all
        expect(File.file?(scratch.app_log)).to be(true)
        expect(File.file?(scratch.mail_log)).to be(true)
        # The selftest lane runs no application code, so nothing appended.
        expect(File.size(scratch.app_log)).to eq(0)
        expect(File.size(scratch.mail_log)).to eq(0)
      end
    end

    it 'reports the app log path on stderr and in last.log, ahead of the exit record' do
      probe.with_scratch do |scratch|
        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')
        log = File.read(scratch.last_log)

        line = "[lane:selftest] app log: #{scratch.app_log}\n"
        expect(run.exitstatus).to eq(0), run.all
        expect(run.stderr.lines.last(2)).to eq([line, exit_records(log, 0).first])
        expect(log.lines.last(2)).to eq([line, exit_records(log, 0).first])
        expect(exit_records(log, 0).length).to eq(1)
        # mail.log is raw message content; the runner's own lines name
        # app.log only.
        expect(run.stderr).not_to include('mail.log')
      end
    end

    it 'empties the files before the command runs, and hands it the profile, for --only too' do
      # The stub stands in for `bundle exec rspec <path>`: it prints the
      # names it was given and appends one line to each file, the way a test
      # process would. Finding exactly that line afterwards shows the
      # truncation came first.
      fake_bundle = <<~SH
        echo "stub-env:${LANES_APP_LOG_FILE}|${LANES_MAIL_LOG_FILE}|${LANES_APP_LOG_CONSOLE}|${LANES_RSPEC_CONSOLE}|${LOG_LEVEL-unset}|${DEBUG_LOGGERS-unset}"
        echo "appended-by-the-run" >> "${LANES_APP_LOG_FILE}"
        echo "mailed-by-the-run" >> "${LANES_MAIL_LOG_FILE}"
      SH

      probe.with_scratch do |scratch|
        File.binwrite(scratch.app_log, "previous-run-app-log\n")
        File.binwrite(scratch.mail_log, "previous-run-mail-log\n")

        probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
          run = probe.run(
            'selftest', '--overlay', scratch.overlay,
            '--capture-logs', '--log-console', 'off', '--quiet',
            '--only', 'spec/unit/lanes/capture_logs_spec.rb',
            env: { 'PATH' => fake_path },
          )

          expect(run.exitstatus).to eq(0), run.all
          expect(run.stdout)
            .to include("stub-env:#{scratch.app_log}|#{scratch.mail_log}|off|quiet|unset|unset")
          expect(File.read(scratch.app_log)).to eq("appended-by-the-run\n")
          expect(File.read(scratch.mail_log)).to eq("mailed-by-the-run\n")
          expect(run.stderr).to include("[lane:selftest] app log: #{scratch.app_log}")
        end
      end
    end
  end

  describe 'a run that does not ask for them' do
    it 'removes the files an earlier capture left, so they never outlive their last.log' do
      probe.with_scratch do |scratch|
        File.binwrite(scratch.app_log, 'previous-run-app-log')
        File.binwrite(scratch.mail_log, 'previous-run-mail-log')

        run = probe.run('selftest', '--overlay', scratch.overlay)

        expect(run.exitstatus).to eq(0), run.all
        expect(File.exist?(scratch.app_log)).to be(false)
        expect(File.exist?(scratch.mail_log)).to be(false)
        expect(run.all).not_to include('app log:')
        expect(File.read(scratch.last_log)).not_to include('app log:')
      end
    end

    it 'creates neither file' do
      probe.with_scratch do |scratch|
        run = probe.run('selftest', '--overlay', scratch.overlay, '--log-console', 'warn')

        expect(run.exitstatus).to eq(0), run.all
        expect(Dir.children(scratch.directory)).to eq(['last.log'])
      end
    end

    it 'leaves them alone for a console, which is not a run' do
      fake_bundle = <<~SH
        echo "fake-bundle:$*"
        exit 0
      SH

      probe.with_scratch do |scratch|
        File.binwrite(scratch.app_log, 'previous-run-app-log')
        File.binwrite(scratch.mail_log, 'previous-run-mail-log')

        probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
          run = probe.run('selftest', '--overlay', scratch.overlay, '--console', env: { 'PATH' => fake_path })

          expect(run.exitstatus).to eq(0), run.all
          expect(run.stdout).to include('fake-bundle:exec bin/ots console')
          expect(File.binread(scratch.app_log)).to eq('previous-run-app-log')
          expect(File.binread(scratch.mail_log)).to eq('previous-run-mail-log')
        end
      end
    end
  end

  describe 'a file that cannot be created' do
    # Exit 73 (EX_CANTCREAT), a diagnostic naming the path on stderr and in
    # last.log, one exit record, and no task: the selftest task prints its
    # markers on stdout, so their absence is the evidence that nothing ran.
    def expect_refused(run, scratch, *phrases)
      log = File.read(scratch.last_log)

      expect(run.exitstatus).to eq(73), run.all
      expect(run.stderr).to include(*phrases)
      expect(log).to include(*phrases)
      expect(exit_records(log, 73).length).to eq(1)
      expect(log).to end_with(exit_records(log, 73).first)
      expect(run.all).not_to include('--- lane:selftest')
      expect(run.all).not_to include('app log:')
    end

    it 'stops before any task when app.log is a directory' do
      probe.with_scratch do |scratch|
        FileUtils.mkdir_p(scratch.app_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'is a directory')
      end
    end

    it 'stops before any task when mail.log is a directory' do
      probe.with_scratch do |scratch|
        FileUtils.mkdir_p(scratch.mail_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs', '--log-console', 'off')

        expect_refused(run, scratch, scratch.mail_log, 'is a directory')
      end
    end

    # A device stands in for anything that exists and is not a regular file.
    # It accepts the truncation, so without the check the run would go on
    # and report the file as removed at the end (exit 74); a FIFO in its
    # place would block the runner outright.
    it 'stops before any task when app.log is not a regular file' do
      probe.with_scratch do |scratch|
        File.symlink(File::NULL, scratch.app_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'not a regular file')
        expect(File.symlink?(scratch.app_log)).to be(true)
      end
    end

    # `-f` follows a link, so one to a regular file would pass as the
    # runner's own and the truncation would empty a file outside the run
    # directory.
    it 'stops before any task, leaving the target alone, when app.log is a symbolic link to a file' do
      probe.with_scratch do |scratch|
        target = File.join(scratch.directory, 'not-the-runners.txt')
        File.write(target, "kept\n")
        File.symlink(target, scratch.app_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'symbolic link')
        expect(File.read(target)).to eq("kept\n")
        expect(File.symlink?(scratch.app_log)).to be(true)
      end
    end

    it 'stops before any task when the run directory is not writable' do
      skip 'file permissions do not bind the superuser' if Process.uid.zero?

      probe.with_scratch do |scratch|
        # last.log already exists, as it does on every run after the first,
        # so the runner can still seed it; the new files cannot be created.
        File.write(scratch.last_log, "previous-run-log\n")
        FileUtils.chmod(0o555, scratch.directory)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'cannot be created or truncated')
        expect(File.exist?(scratch.app_log)).to be(false)
      end
    end

    it 'stops before any task when an existing app.log is not writable' do
      skip 'file permissions do not bind the superuser' if Process.uid.zero?

      probe.with_scratch do |scratch|
        File.binwrite(scratch.app_log, 'previous-run-app-log')
        FileUtils.chmod(0o444, scratch.app_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'cannot be created or truncated')
        expect(File.binread(scratch.app_log)).to eq('previous-run-app-log')
      end
    end
  end

  describe 'a capture that did not stay whole' do
    # The runner created the files and the test processes opened them, so
    # what is left to catch is a failure during the run. The stub stands in
    # for `bundle exec rspec <path>` and does to the files what a misbehaving
    # run would.
    def run_only(scratch, fake_bundle)
      probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
        probe.run(
          'selftest', '--overlay', scratch.overlay, '--capture-logs',
          '--only', 'spec/unit/lanes/capture_logs_spec.rb',
          env: { 'PATH' => fake_path },
        )
      end
    end

    it 'turns a green run into exit 74 when app.log is gone at the end' do
      probe.with_scratch do |scratch|
        run = run_only(scratch, 'rm -f "${LANES_APP_LOG_FILE}"')
        log = File.read(scratch.last_log)

        expect(run.exitstatus).to eq(74), run.all
        expect(run.stderr).to include("#{scratch.app_log} was removed during the run")
        expect(log).to include("#{scratch.app_log} was removed during the run")
        expect(run.stderr).to include("app log: #{scratch.app_log} (incomplete)\n")
        expect(log).to end_with(exit_records(log, 74).first)
      end
    end

    it 'does the same when mail.log is gone at the end' do
      probe.with_scratch do |scratch|
        run = run_only(scratch, 'rm -f "${LANES_MAIL_LOG_FILE}"')

        expect(run.exitstatus).to eq(74), run.all
        expect(run.stderr).to include("#{scratch.mail_log} was removed during the run")
      end
    end

    it "keeps a failed run's own exit code, and still says the capture is incomplete" do
      probe.with_scratch do |scratch|
        run = run_only(scratch, "rm -f \"${LANES_APP_LOG_FILE}\"\nexit 3")
        log = File.read(scratch.last_log)

        expect(run.exitstatus).to eq(3), run.all
        expect(run.stderr).to include('error: log capture is incomplete')
        expect(exit_records(log, 3).length).to eq(1)
      end
    end

    it 'says nothing when both files are still there' do
      probe.with_scratch do |scratch|
        run = run_only(scratch, 'echo "appended-by-the-run" >> "${LANES_APP_LOG_FILE}"')

        expect(run.exitstatus).to eq(0), run.all
        expect(run.all).not_to include('incomplete')
      end
    end

    # A process that finds its log file missing creates it again (the
    # application opens with O_CREAT), so a file being there at the end does
    # not show that it holds the whole run. The runner hard-links each file
    # at the start, compares at the end, and then removes the links: a link
    # left behind would keep the space of a log that is deleted afterwards.
    describe 'a file that was removed and created again' do
      # The links exist only during the run, so the stub reports them.
      def report_links(scratch)
        <<~SH
          [ "${LANES_APP_LOG_FILE}" -ef "#{scratch.app_anchor}" ] && echo "app-log-linked"
          [ "${LANES_MAIL_LOG_FILE}" -ef "#{scratch.mail_anchor}" ] && echo "mail-log-linked"
          exit 0
        SH
      end

      it 'makes a hard link beside each file for the length of the run' do
        probe.with_scratch do |scratch|
          run = run_only(scratch, report_links(scratch))

          expect(run.exitstatus).to eq(0), run.all
          expect(run.all).to include("app-log-linked\n", "mail-log-linked\n")
        end
      end

      it 'links the files of this run when a run that never reached its end left its links' do
        probe.with_scratch do |scratch|
          File.write(scratch.app_log, "earlier run\n")
          File.link(scratch.app_log, scratch.app_anchor)
          File.write(scratch.mail_anchor, "earlier run\n")

          run = run_only(scratch, report_links(scratch))

          expect(run.exitstatus).to eq(0), run.all
          expect(run.all).to include("app-log-linked\n", "mail-log-linked\n")
        end
      end

      it 'removes the links at the end of a run of the lane tasks' do
        probe.with_scratch do |scratch|
          run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

          expect(run.exitstatus).to eq(0), run.all
          expect(Dir.children(scratch.directory)).to contain_exactly('app.log', 'mail.log', 'last.log')
          expect(File.stat(scratch.app_log).nlink).to eq(1)
          expect(File.stat(scratch.mail_log).nlink).to eq(1)
        end
      end

      it 'removes the links at the end of a run that failed with its capture whole' do
        probe.with_scratch do |scratch|
          run = run_only(scratch, 'exit 1')

          expect(run.exitstatus).to eq(1), run.all
          expect(File.exist?(scratch.app_anchor)).to be(false)
          expect(File.exist?(scratch.mail_anchor)).to be(false)
        end
      end

      it 'turns a green run into exit 74 when app.log is not the file the run started with' do
        probe.with_scratch do |scratch|
          recreate = <<~SH
            echo "before" >> "${LANES_APP_LOG_FILE}"
            rm -f "${LANES_APP_LOG_FILE}"
            echo "after" >> "${LANES_APP_LOG_FILE}"
          SH
          run = run_only(scratch, recreate)

          expect(run.exitstatus).to eq(74), run.all
          expect(run.stderr).to include("#{scratch.app_log} is not the file this run started with")
          expect(File.read(scratch.app_log)).to eq("after\n")
          # The link that no longer matches stays, with what was written
          # before the removal. The one that still matches goes.
          expect(File.read(scratch.app_anchor)).to eq("before\n")
          expect(File.exist?(scratch.mail_anchor)).to be(false)
        end
      end

      it 'keeps the link of a log that is gone at the end, and replaces it at the next start' do
        probe.with_scratch do |scratch|
          run = run_only(scratch, 'echo "before" >> "${LANES_APP_LOG_FILE}"; rm -f "${LANES_APP_LOG_FILE}"')

          expect(run.exitstatus).to eq(74), run.all
          expect(File.read(scratch.app_anchor)).to eq("before\n")

          run = run_only(scratch, 'true')

          expect(run.exitstatus).to eq(0), run.all
          expect(File.exist?(scratch.app_anchor)).to be(false)
        end
      end

      it 'says so when the link itself is gone' do
        probe.with_scratch do |scratch|
          run = run_only(scratch, %(rm -f "#{scratch.app_anchor}"))

          expect(run.exitstatus).to eq(74), run.all
          expect(run.stderr).to include("#{scratch.app_anchor} is gone")
        end
      end

      it 'does the same for mail.log' do
        probe.with_scratch do |scratch|
          run = run_only(scratch, 'rm -f "${LANES_MAIL_LOG_FILE}"; : >> "${LANES_MAIL_LOG_FILE}"')

          expect(run.exitstatus).to eq(74), run.all
          expect(run.stderr).to include("#{scratch.mail_log} is not the file this run started with")
        end
      end

      it 'removes the links with the files on a run that captures nothing' do
        probe.with_scratch do |scratch|
          probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')
          # As a run that ended before its epilogue leaves them.
          File.link(scratch.app_log, scratch.app_anchor)
          File.link(scratch.mail_log, scratch.mail_anchor)
          File.write(scratch.write_failed, "left by an earlier run\n")

          run = probe.run('selftest', '--overlay', scratch.overlay)

          expect(run.exitstatus).to eq(0), run.all
          expect(Dir.children(scratch.directory)).to eq(['last.log'])
        end
      end
    end

    # A write to the log file that fails after it was opened raises nothing
    # in the application. The application's file sink reports I/O errors
    # itself (SetupLoggers::FileSink#log): to listeners, one of which the
    # test profile uses to write <app log>.write-failed, and on standard
    # error. The runner looks for the marker, and failing that for the line
    # in last.log. Both are produced here by the real sink and the real
    # listener, so a change to either fails these examples instead of
    # disarming the check.
    describe 'a write the application could not complete' do
      include LaneProbe::FailingWrites

      # Fail one write to +path+ through the application's sink, with the
      # profile's listener watching +watched+. Returns the line the sink
      # printed on standard error.
      def failed_write_report(path, watched: path)
        sink_class = Onetime::Initializers::SetupLoggers::FileSink
        listeners  = sink_class.write_failure_listeners
        saved      = listeners.dup
        listeners.replace([Lanes::LogCapture::WriteFailureMarker.new(watched)])

        sink = break_file_sink(sink_class.new(path, append: true), Errno::ENOSPC.new('probe'))
        log_through(sink, Errno::ENOSPC).chomp
      ensure
        listeners&.replace(saved)
      end

      # The selftest task prints its environment, so an overlay variable is
      # a way to put a chosen line into the run's output, and so into
      # last.log, without a fixture lane.
      def print_in_run(scratch, line)
        File.write(scratch.overlay_path, "CAPTURE_LOGS_SPEC_STDERR_LINE=#{Shellwords.escape(line)}\n")
      end

      it 'turns a green run into exit 74 when a test process recorded one' do
        probe.with_scratch do |scratch|
          # The stub writes the marker the way the listener does, during the
          # run: the runner removes one it finds at the start.
          marker_line = nil
          Dir.mktmpdir('capture-logs-marker') do |dir|
            elsewhere = File.join(dir, 'app.log')
            failed_write_report(elsewhere)
            marker_line = File.read("#{elsewhere}.write-failed")
          end

          run = run_only(scratch, "printf '%s' #{Shellwords.escape(marker_line)} > \"${LANES_APP_LOG_FILE}.write-failed\"")

          expect(run.exitstatus).to eq(74), run.all
          expect(run.stderr).to include('could not write to the app log', marker_line.chomp)
          expect(run.stderr).to include("app log: #{scratch.app_log} (incomplete)\n")
          expect(File.read(scratch.last_log)).to include('could not write to the app log')
        end
      end

      it 'removes a marker an earlier run left, so it is not held against this one' do
        probe.with_scratch do |scratch|
          File.write(scratch.write_failed, "pid 1: Errno::ENOSPC: left by an earlier run\n")

          run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

          expect(run.exitstatus).to eq(0), run.all
          expect(File.exist?(scratch.write_failed)).to be(false)
          expect(run.all).not_to include('incomplete')
        end
      end

      it "turns a green run into exit 74 when the sink's own report is in the run output" do
        probe.with_scratch do |scratch|
          line = failed_write_report(scratch.app_log, watched: '/nowhere/app.log')
          expect(File.exist?(scratch.write_failed)).to be(false)
          print_in_run(scratch, line)

          run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

          expect(run.exitstatus).to eq(74), run.all
          expect(File.read(scratch.last_log)).to include(line)
          expect(run.stderr).to include('reported a failed write to the app log')
          expect(File.file?(scratch.app_log)).to be(true)
        end
      end

      it 'is not held against a run when the report names another log file' do
        probe.with_scratch do |scratch|
          line = Dir.mktmpdir('capture-logs-other') { |dir| failed_write_report(File.join(dir, 'app.log')) }
          print_in_run(scratch, line)

          run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

          expect(run.exitstatus).to eq(0), run.all
          expect(File.read(scratch.last_log)).to include(line)
          expect(run.all).not_to include('incomplete')
        end
      end

      # SemanticLogger prints `Failed to log to appender: <appender>` for any
      # exception raised while an appender runs. Bunny raises ShutdownSignal
      # into its reader thread when a session closes, and a thread that is
      # logging at that moment produces the line on every RabbitMQ lane. It is
      # not a failed write, and a green lane must stay green.
      it "stays green when SemanticLogger's own appender-failure line is in the run output" do
        line = '2026-10-06 12:00:00.000000 E [1:bunny-reader] SemanticLogger::Appenders -- ' \
               'Failed to log to appender: Onetime::Initializers::SetupLoggers::FileSink -- ' \
               'Exception: Bunny::Session::ShutdownSignal: interrupted'

        probe.with_scratch do |scratch|
          print_in_run(scratch, line)

          run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

          expect(run.exitstatus).to eq(0), run.all
          expect(File.read(scratch.last_log)).to include(line)
          expect(run.all).not_to include('incomplete')
        end
      end

      it 'is not looked for on a run that captures nothing' do
        probe.with_scratch do |scratch|
          print_in_run(scratch, failed_write_report(scratch.app_log, watched: '/nowhere/app.log'))

          run = probe.run('selftest', '--overlay', scratch.overlay)

          expect(run.exitstatus).to eq(0), run.all
          expect(run.all).not_to include('incomplete')
        end
      end
    end
  end

  describe 'setup that fails after the files exist' do
    it 'leaves both files in place and reports them with the failure' do
      fake_bundle = <<~SH
        echo "fake-pg-stdout:$*"
        exit 41
      SH
      overlay = <<~ENV
        AUTH_DATABASE_URL='postgresql://onetime_user:testpass@127.0.0.1:2154/onetime_auth_test'
      ENV

      probe.with_scratch(overlay) do |scratch|
        File.binwrite(scratch.app_log, 'previous-run-app-log')

        probe.with_open_port(2154) do
          probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
            run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs',
                            env: { 'PATH' => fake_path })
            log = File.read(scratch.last_log)
            line = "[lane:selftest] app log: #{scratch.app_log}\n"

            expect(run.exitstatus).to eq(41), run.all
            expect(log).to include('fake-pg-stdout:exec ruby tests/lanes/support/provision_pg_database.rb')
            expect(File.file?(scratch.app_log)).to be(true)
            expect(File.size(scratch.app_log)).to eq(0)
            expect(File.file?(scratch.mail_log)).to be(true)
            expect(log.lines.last(2)).to eq([line, exit_records(log, 41).first])
            expect(run.stderr.lines.last(2)).to eq([line, exit_records(log, 41).first])
            expect(run.all).not_to include('--- lane:selftest')
          end
        end
      end
    end
  end
end
