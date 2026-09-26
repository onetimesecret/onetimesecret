# spec/unit/lanes/last_log_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'securerandom'
require 'socket'
require 'tmpdir'

module LaneLastLogProbe
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

  def log_path(overlays)
    File.join(repo_root, 'tmp', 'lanes', 'selftest', overlays, 'last.log')
  end

  def run(*args, env: {})
    Open3.capture2e(
      { 'CI' => nil, 'RSPEC_OUTPUT_FILE' => nil }.merge(env),
      runner, *args, chdir: repo_root
    )
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

  def with_probe_log(overlay_contents = '')
    overlay = "last-log-#{Process.pid}-#{SecureRandom.hex(4)}"
    overlay_path = File.join(repo_root, 'tests', 'lanes', 'overlays', "#{overlay}.env")
    directory = File.dirname(log_path(overlay))
    File.write(overlay_path, overlay_contents)
    FileUtils.mkdir_p(directory)
    yield overlay, log_path(overlay)
  ensure
    FileUtils.rm_f(overlay_path) if overlay_path
    FileUtils.rm_rf(directory) if directory
  end
end

RSpec.describe 'tests/lanes/run last.log coverage' do
  let(:probe) { LaneLastLogProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'preserves the previous log when argument handling fails before initialization' do
    probe.with_probe_log do |overlay, path|
      File.binwrite(path, 'previous-run-log')

      output, status = probe.run('selftest', '--overlay', overlay, '--bogus')

      expect(status.exitstatus).to eq(64), output
      expect(File.binread(path)).to eq('previous-run-log')
    end
  end

  it 'captures a PostgreSQL provisioning failure and preserves its status' do
    fake_bundle = <<~SH
      echo "fake-pg-stdout:$*"
      echo "fake-pg-stderr:$*" >&2
      exit 41
    SH
    overlay = <<~ENV
      AUTH_DATABASE_URL='postgresql://onetime_user:testpass@127.0.0.1:2154/onetime_auth_test'
    ENV

    probe.with_probe_log(overlay) do |overlay_name, path|
      probe.with_open_port(2154) do
        probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
          output, status = probe.run('selftest', '--overlay', overlay_name, env: { 'PATH' => fake_path })
          log = File.read(path)

          expect(status.exitstatus).to eq(41), output
          expect(log).to include('fake-pg-stdout:exec ruby tests/lanes/support/provision_pg_database.rb')
          expect(log).to include('fake-pg-stderr:exec ruby tests/lanes/support/provision_pg_database.rb')
          expect(log.lines.grep(/^\[lane:selftest\] log: .* \(exit 41\)$/).length).to eq(1)
        end
      end
    end
  end

  it 'captures a RabbitMQ provisioning failure and preserves its status' do
    fake_ruby = <<~SH
      echo "fake-rabbitmq-stdout:$*"
      echo "fake-rabbitmq-stderr:$*" >&2
      exit 42
    SH
    overlay = "RABBITMQ_URL='amqp://guest:guest@127.0.0.1:2156'\n"

    probe.with_probe_log(overlay) do |overlay_name, path|
      probe.with_fake_commands('ruby' => fake_ruby) do |fake_path|
        output, status = probe.run('selftest', '--overlay', overlay_name, env: { 'PATH' => fake_path })
        log = File.read(path)

        expect(status.exitstatus).to eq(42), output
        expect(log).to include('fake-rabbitmq-stdout:tests/lanes/support/provision_rabbitmq_vhost.rb')
        expect(log).to include('fake-rabbitmq-stderr:tests/lanes/support/provision_rabbitmq_vhost.rb')
        expect(log.lines.grep(/^\[lane:selftest\] log: .* \(exit 42\)$/).length).to eq(1)
      end
    end
  end

  it 'preserves RabbitMQ state mode and the previous log for a console' do
    fake_ruby = <<~SH
      echo "fake-rabbitmq:$*"
      exit 0
    SH
    fake_bundle = <<~SH
      echo "fake-bundle:$*"
      exit 0
    SH
    overlay = "RABBITMQ_URL='amqp://guest:guest@127.0.0.1:2156'\n"

    probe.with_probe_log(overlay) do |overlay_name, path|
      File.binwrite(path, 'previous-run-log')
      probe.with_fake_commands('ruby' => fake_ruby, 'bundle' => fake_bundle) do |fake_path|
        output, status = probe.run(
          'selftest', '--overlay', overlay_name, '--console',
          env: { 'PATH' => fake_path },
        )

        expect(status).to be_success, output
        expect(output).to include('fake-rabbitmq:tests/lanes/support/provision_rabbitmq_vhost.rb --preserve-existing')
        expect(output).to include('fake-bundle:exec bin/ots console')
        expect(File.binread(path)).to eq('previous-run-log')
        expect(output).not_to include('[lane:selftest] log:')
      end
    end
  end
end
