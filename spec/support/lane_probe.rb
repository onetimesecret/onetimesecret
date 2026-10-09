# spec/support/lane_probe.rb
#
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'securerandom'
require 'socket'
require 'stringio'
require 'tmpdir'

# Harness shared by the specs that start tests/lanes/run, or a script beside
# it, as a subprocess (spec/unit/lanes). A spec's own probe module extends
# this one and adds what only that spec needs; a method it defines itself
# (a `run` with other defaults, say) takes precedence.
module LaneProbe
  # A finished subprocess, stdout and stderr apart: where a diagnostic lands
  # is part of what is asserted.
  Run = Struct.new(:stdout, :stderr, :status) do
    def exitstatus = status.exitstatus
    def all        = "#{stdout}#{stderr}"
  end

  # A run directory of its own under tmp/lanes/selftest/ and the overlay name
  # that selects it. The runner keys the directory by overlay set, so no
  # example shares last.log or the captured logs with another run.
  Scratch = Struct.new(:overlay, :directory) do
    def last_log = File.join(directory, 'last.log')
    def app_log  = File.join(directory, 'app.log')
    def mail_log = File.join(directory, 'mail.log')

    # The hard links the runner makes beside the two log files, and the file
    # a test process records a failed write in.
    def app_anchor   = File.join(directory, '.app.log.anchor')
    def mail_anchor  = File.join(directory, '.mail.log.anchor')
    def write_failed = "#{app_log}.write-failed"

    def overlay_path = LaneProbe.overlay_path(overlay)
  end

  extend self

  def repo_root
    File.expand_path('../..', __dir__)
  end

  def runner
    File.join(repo_root, 'tests', 'lanes', 'run')
  end

  # The floor the runner enforces, read from the same pin file it reads: a
  # literal here would be a third copy of the number (runner, doctor, spec),
  # and the first one to go stale silently skips every spec that uses it.
  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(repo_root, '.bash-version')).strip)
  end

  # The runner's shebang is `#!/usr/bin/env bash`, so the bash that matters
  # is the first one on PATH: not the shell that launched RSpec, and on macOS
  # not /bin/bash either.
  def path_bash_major
    return @path_bash_major if defined?(@path_bash_major)

    out, status = Open3.capture2e('bash', '-c', 'echo "${BASH_VERSINFO[0]}"')
    @path_bash_major = status.success? ? Integer(out.strip, exception: false) : nil
  end

  # Why the runner cannot start here, or nil when it can.
  def bash_missing
    major = path_bash_major
    "bash #{bash_floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < bash_floor
  end

  # The runner with stdout and stderr apart. CI is removed so the lane keeps
  # its derived datastore index, RSPEC_OUTPUT_FILE because a nested run has
  # no business with the outer run's results path, and LANES_NO_AUTOSTART is
  # set because a spec must not start containers.
  def run(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      { 'CI' => nil, 'RSPEC_OUTPUT_FILE' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner, *args, chdir: repo_root
    )
    Run.new(stdout, stderr, status)
  end

  def overlay_path(name)
    File.join(repo_root, 'tests', 'lanes', 'overlays', "#{name}.env")
  end

  # A throwaway overlay under a name no other example or process in this
  # checkout picks, removed whatever the block does.
  def with_overlay(contents = '')
    name = "lane-probe-#{Process.pid}-#{SecureRandom.hex(4)}"
    path = overlay_path(name)
    File.write(path, contents)
    yield name
  ensure
    FileUtils.rm_f(path) if path
  end

  # A throwaway overlay and the selftest run directory it selects, both
  # removed afterwards.
  def with_scratch(overlay_contents = '')
    with_overlay(overlay_contents) do |overlay|
      directory = File.join(repo_root, 'tmp', 'lanes', 'selftest', overlay)
      FileUtils.mkdir_p(directory)
      yield Scratch.new(overlay, directory)
    ensure
      if directory && File.directory?(directory)
        # An example may have taken write permission away from the directory.
        FileUtils.chmod(0o755, directory)
        FileUtils.rm_rf(directory)
      end
    end
  end

  # A directory of stub commands put ahead of PATH: { name => shell body }.
  # Yields the PATH value to hand the runner.
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

  # Holds a port open for the runner's preflight, unless a service already
  # listens there.
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

  # For examples that make Onetime::Initializers::SetupLoggers::FileSink fail
  # a write. Include it in the example group.
  module FailingWrites
    # Swap the sink's file handle for one whose write raises +error+. The
    # stock appender retries once after a reopen, which would put a working
    # handle back, so reopen does nothing here. A plain object, not a double:
    # the sink closes it when it is removed after the example.
    def break_file_sink(sink, error)
      broken = Object.new
      broken.define_singleton_method(:write) { |*| raise error }
      broken.define_singleton_method(:close) { nil }
      broken.define_singleton_method(:flush) { nil }
      sink.instance_variable_set(:@file, broken)
      allow(sink).to receive(:reopen)
      sink
    end

    # Log one event through +sink+, which must raise +error_class+, and
    # return what was printed on standard error meanwhile.
    def log_through(sink, error_class)
      was     = $stderr
      $stderr = StringIO.new
      event   = SemanticLogger::Log.new('LaneProbe', :error).tap { |log| log.assign(message: 'an event the file could not take') }
      expect { sink.log(event) }.to raise_error(error_class)
      $stderr.string
    ensure
      $stderr = was
    end
  end
end

# Skips an example where the runner cannot start: it needs bash
# LaneProbe.bash_floor or newer first on PATH.
RSpec.shared_context 'with the lane runner bash' do
  before do
    missing = LaneProbe.bash_missing
    skip missing if missing
  end
end
