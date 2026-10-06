# spec/unit/lanes/capture_logs_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'securerandom'
require 'socket'
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
# the real one on PATH, as last_log_spec.rb does.
module LaneCaptureProbe
  Run = Struct.new(:stdout, :stderr, :status) do
    def exitstatus = status.exitstatus
    def all        = "#{stdout}#{stderr}"
  end

  # One run directory under tmp/lanes/selftest/ and the overlay name that
  # selects it.
  Scratch = Struct.new(:overlay, :directory) do
    def app_log  = File.join(directory, 'app.log')
    def mail_log = File.join(directory, 'mail.log')
    def last_log = File.join(directory, 'last.log')
  end

  module_function

  def repo_root
    File.expand_path('../../..', __dir__)
  end

  def runner
    File.join(repo_root, 'tests', 'lanes', 'run')
  end

  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(repo_root, '.bash-version')).strip)
  end

  def path_bash_major
    return @path_bash_major if defined?(@path_bash_major)

    out, status = Open3.capture2e('bash', '-c', 'echo "${BASH_VERSINFO[0]}"')
    @path_bash_major = status.success? ? Integer(out.strip, exception: false) : nil
  end

  # stdout and stderr apart: where a diagnostic lands is part of what is
  # asserted. CI is removed so the lane keeps its derived datastore index
  # (and so the provisioning step the PostgreSQL example needs is reached);
  # RSPEC_OUTPUT_FILE because the runner refuses --quiet beside it.
  def run(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      { 'CI' => nil, 'RSPEC_OUTPUT_FILE' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner, *args, chdir: repo_root
    )
    Run.new(stdout, stderr, status)
  end

  def with_scratch(overlay_contents = '')
    overlay      = "capture-logs-#{Process.pid}-#{SecureRandom.hex(4)}"
    overlay_path = File.join(repo_root, 'tests', 'lanes', 'overlays', "#{overlay}.env")
    directory    = File.join(repo_root, 'tmp', 'lanes', 'selftest', overlay)
    File.write(overlay_path, overlay_contents)
    FileUtils.mkdir_p(directory)
    yield Scratch.new(overlay, directory)
  ensure
    FileUtils.rm_f(overlay_path) if overlay_path
    if directory && File.directory?(directory)
      # An example may have taken write permission away from the directory.
      FileUtils.chmod(0o755, directory)
      FileUtils.rm_rf(directory)
    end
  end

  def with_fake_commands(commands)
    Dir.mktmpdir('ots-lane-commands') do |dir|
      commands.each do |name, body|
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\n#{body}\n")
        File.chmod(0o755, path)
      end
      yield [dir, ENV.fetch('PATH')].join(File::PATH_SEPARATOR)
    end
  end

  def with_open_port(port)
    server = begin
      TCPServer.new('127.0.0.1', port)
    rescue Errno::EADDRINUSE
      nil
    end
    yield
  ensure
    server&.close
  end
end

RSpec.describe 'tests/lanes/run --capture-logs files' do
  let(:probe) { LaneCaptureProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

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
    # Exit 73 (EX_CANTCREAT), a diagnostic on stderr and in last.log, one
    # exit record, and no task: the selftest task prints its markers on
    # stdout, so their absence is the evidence that nothing ran.
    def expect_refused(run, scratch, path, reason)
      log = File.read(scratch.last_log)

      expect(run.exitstatus).to eq(73), run.all
      expect(run.stderr).to include("error: --capture-logs cannot create #{path}")
      expect(run.stderr).to include(reason)
      expect(log).to include("error: --capture-logs cannot create #{path}")
      expect(log).to include(reason)
      expect(exit_records(log, 73).length).to eq(1)
      expect(log).to end_with(exit_records(log, 73).first)
      expect(run.all).not_to include('--- lane:selftest')
      expect(run.all).not_to include('app log:')
    end

    it 'stops before any task when app.log is a directory' do
      probe.with_scratch do |scratch|
        FileUtils.mkdir_p(scratch.app_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs')

        expect_refused(run, scratch, scratch.app_log, 'the path is a directory')
      end
    end

    it 'stops before any task when mail.log is a directory' do
      probe.with_scratch do |scratch|
        FileUtils.mkdir_p(scratch.mail_log)

        run = probe.run('selftest', '--overlay', scratch.overlay, '--capture-logs', '--log-console', 'off')

        expect_refused(run, scratch, scratch.mail_log, 'the path is a directory')
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
