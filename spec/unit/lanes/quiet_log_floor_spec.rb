# spec/unit/lanes/quiet_log_floor_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Regression harness for the app-log floor `tests/lanes/run --quiet` sets.
#
# The runner cannot lower one global level: every category listed under
# `loggers:` in spec/logging.test.yaml overrides SemanticLogger's default on
# each boot (initializers/setup_loggers.rb), so `--quiet` exports LOG_LEVEL
# for the categories the yaml does not name AND DEBUG_LOGGERS with an
# explicit `<name>:error` for every category the initializer defines. That
# list is hand-written bash. A category added to the initializer's
# logger_definitions (and pinned at warn/info in the yaml) without a matching
# runner entry would not fail anything — its lines would just come back,
# tens of thousands at a time. This pins the two lists to each other.
#
# Method: `--print-key` reports the derivation without touching a service,
# against the `selftest` lane (no codegen, no ports), so the check is one
# process spawn.
RSpec.describe 'tests/lanes/run --quiet app-log floor' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:runner) { File.join(repo_root, 'tests', 'lanes', 'run') }

  def print_key(*flags)
    out, status = Open3.capture2e({ 'RSPEC_OUTPUT_FILE' => nil }, runner, 'selftest', *flags, '--print-key', chdir: repo_root)
    raise "runner exited #{status.exitstatus}:\n#{out}" unless status.success?

    out.lines.grep(/\Alog_level=/).first.to_s.strip
  end

  it 'floors every logger the initializer defines at error under --quiet' do
    line = print_key('--quiet')
    expect(line).to match(/\Alog_level=error debug_loggers=\S+\z/)

    entries = line[/debug_loggers=(\S+)/, 1].split(',').map { |e| e.split(':', 2) }
    expect(entries.map(&:last).uniq).to eq(['error'])
    expect(entries.map(&:first).sort).to eq(Onetime::Initializers::SetupLoggers.logger_definitions.keys.sort)
  end

  it 'sets the same floor under --quiet-logs, the flag CI runs every lane with' do
    expect(print_key('--quiet-logs')).to eq(print_key('--quiet'))
  end

  it 'sets neither knob without --quiet' do
    expect(print_key).to eq('log_level=none debug_loggers=none')
  end

  # The floor discards an event where it is generated, so no destination can
  # recover it. --capture-logs exists to keep those events (#4683): under it
  # the runner sets no floor at all, and --log-console decides what the
  # console shows of what the categories admit.
  describe 'under --capture-logs' do
    [
      %w[--capture-logs],
      %w[--capture-logs --quiet],
      %w[--quiet --capture-logs],
      %w[--capture-logs --log-console off],
      %w[--capture-logs --log-console off --quiet],
      %w[--capture-logs --log-console error --quiet],
    ].each do |flags|
      it "sets neither knob for: #{flags.join(' ')}" do
        expect(print_key(*flags)).to eq('log_level=none debug_loggers=none')
      end
    end
  end

  it 'keeps the floor for a bare --quiet beside a console threshold' do
    expect(print_key('--quiet', '--log-console', 'warn')).to eq(print_key('--quiet'))
    expect(print_key('--quiet')).to start_with('log_level=error ')
  end
end
