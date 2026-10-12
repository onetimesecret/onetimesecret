# spec/unit/lanes/last_log_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/lane_probe'

module LaneLastLogProbe
  extend LaneProbe

  module_function

  # The RabbitMQ overlay makes the runner's preflight require AMQP (2156) and,
  # off datastore index 0, the management API (12156). Provisioning itself is
  # faked, so only the ports have to answer: hold them open the way the
  # PostgreSQL example holds 2154, or a host without the real service (the
  # macOS installer job runs a bare redis-server) trips the compose autostart.
  def with_rabbitmq_ports_open(&block)
    with_open_port(2156) { with_open_port(12_156, &block) }
  end
end

RSpec.describe 'tests/lanes/run last.log coverage' do
  let(:probe) { LaneLastLogProbe }

  include_context 'with the lane runner bash'

  it 'preserves the previous log when argument handling fails before initialization' do
    probe.with_scratch do |scratch|
      File.binwrite(scratch.last_log, 'previous-run-log')

      run = probe.run('selftest', '--overlay', scratch.overlay, '--bogus')

      expect(run.exitstatus).to eq(64), run.all
      expect(File.binread(scratch.last_log)).to eq('previous-run-log')
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

    probe.with_scratch(overlay) do |scratch|
      probe.with_open_port(2154) do
        probe.with_fake_commands('bundle' => fake_bundle) do |fake_path|
          run = probe.run('selftest', '--overlay', scratch.overlay, env: { 'PATH' => fake_path })
          log = File.read(scratch.last_log)

          expect(run.exitstatus).to eq(41), run.all
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

    probe.with_scratch(overlay) do |scratch|
      probe.with_rabbitmq_ports_open do
        probe.with_fake_commands('ruby' => fake_ruby) do |fake_path|
          run = probe.run('selftest', '--overlay', scratch.overlay, env: { 'PATH' => fake_path })
          log = File.read(scratch.last_log)

          expect(run.exitstatus).to eq(42), run.all
          expect(log).to include('fake-rabbitmq-stdout:tests/lanes/support/provision_rabbitmq_vhost.rb')
          expect(log).to include('fake-rabbitmq-stderr:tests/lanes/support/provision_rabbitmq_vhost.rb')
          expect(log.lines.grep(/^\[lane:selftest\] log: .* \(exit 42\)$/).length).to eq(1)
        end
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

    probe.with_scratch(overlay) do |scratch|
      File.binwrite(scratch.last_log, 'previous-run-log')
      probe.with_rabbitmq_ports_open do
        probe.with_fake_commands('ruby' => fake_ruby, 'bundle' => fake_bundle) do |fake_path|
          run = probe.run(
            'selftest', '--overlay', scratch.overlay, '--console',
            env: { 'PATH' => fake_path },
          )

          expect(run.status).to be_success, run.all
          expect(run.all).to include('fake-rabbitmq:tests/lanes/support/provision_rabbitmq_vhost.rb --preserve-existing')
          expect(run.all).to include('fake-bundle:exec bin/ots console')
          expect(File.binread(scratch.last_log)).to eq('previous-run-log')
          expect(run.all).not_to include('[lane:selftest] log:')
        end
      end
    end
  end
end
