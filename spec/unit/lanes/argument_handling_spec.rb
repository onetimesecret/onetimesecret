# spec/unit/lanes/argument_handling_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'securerandom'
require 'tmpdir'

# The argument surface of tests/lanes/run (#4492): which flag combinations
# the runner accepts, which it refuses with exit 64, what --quiet,
# --capture-logs and --log-console select (#4683), and how a lane-less
# --only and --which resolve through the ownership table. Every example is
# one process spawn against the `selftest` lane with --print-key, which
# returns right after the derivation and before any service, codegen or
# task — so nothing here needs a datastore and a parsing error (exit 64)
# fires before --print-key is honored, which is what makes the nonzero rows
# meaningful. The --only paths only have to exist; --print-key never opens
# them.
#
# RSPEC_OUTPUT_FILE is keep-listed by the runner, so a CI unit lane (which
# sets it through run-test-lane/action.yml) would hand it to every child
# here. Nothing below depends on it any more (--quiet used to refuse a run
# that had it), but a nested run has no business with the outer run's
# results path, so it is removed. The examples about the pairing set it
# themselves.
#
# The log-floor half of --quiet (LOG_LEVEL, DEBUG_LOGGERS) is pinned to the
# initializer's logger table by quiet_log_floor_spec.rb; the ownership table
# itself is checked against rake and the tree on disk by ownership_spec.rb.
module LaneArgumentProbe
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

  # Merged stdout+stderr and the status. The runner prints its --print-key
  # lines on stdout and its refusals on stderr; both matter to the examples.
  def run(*args, env: {}, runner_path: runner, working_directory: repo_root)
    Open3.capture2e(
      { 'RSPEC_OUTPUT_FILE' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner_path, *args, chdir: working_directory
    )
  end

  # One --print-key field, to the end of its line: a path may carry spaces.
  def field(output, key)
    output[/(?:\A|\s)#{Regexp.escape(key)}=(.*)$/, 1]
  end

  # A throwaway overlay file under a name no other example or process in
  # this checkout picks, removed whatever the block does.
  def with_overlay(contents)
    name = "argument-handling-#{Process.pid}-#{SecureRandom.hex(4)}"
    path = File.join(repo_root, 'tests', 'lanes', 'overlays', "#{name}.env")
    File.write(path, contents)
    yield name
  ensure
    FileUtils.rm_f(path) if path
  end
end

RSpec.describe 'tests/lanes/run argument handling' do
  let(:probe) { LaneArgumentProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  describe 'with a lane named' do
    # `<expected exit>, <argv after the lane>`
    [
      [0,  %w[--print-key]],
      [0,  %w[--quiet --print-key]],
      [64, %w[--bogus --print-key]],
      [64, %w[--print-key --bogus]],
      [64, %w[--print-key -- --only-failures]],
      [0,  %w[--print-key --only spec/unit/lanes/hermetic_boundary_spec.rb -- --only-failures]],
      [0,  %w[--print-key --only spec/unit/lanes/hermetic_boundary_spec.rb --]],
      [0,  %w[--print-key --only spec/unit/lanes]],
      [64, %w[--print-key --only try/unit]],
      [64, %w[--print-key --only apps/web/auth/try]],
      [64, %w[--print-key --only apps/api/domains/try]],
      [64, %w[--print-key --only try/unit/base_view_try.rb -- --only-failures]],
      [64, %w[--print-key --only try/unit/base_view_try.rb --only spec/unit/lanes/hermetic_boundary_spec.rb]],
      [0,  %w[--console --print-key]],
      [0,  %w[--console --overlay billing --print-key]],
      [64, %w[--console --only spec/unit/lanes/hermetic_boundary_spec.rb --print-key]],
      [64, %w[--console --quiet --print-key]],
      [64, %w[--console --skip-codegen --print-key]],
      [64, %w[--console -- --only-failures]],
      [0,  %w[--capture-logs --print-key]],
      [0,  %w[--capture-logs --log-console off --print-key]],
      [0,  %w[--capture-logs --log-console off --quiet --print-key]],
      [0,  %w[--capture-logs --log-console error --print-key]],
      [0,  %w[--capture-logs --only spec/unit/lanes/hermetic_boundary_spec.rb --print-key]],
      [0,  %w[--log-console trace --print-key]],
      [0,  %w[--log-console debug --print-key]],
      [0,  %w[--log-console info --print-key]],
      [0,  %w[--log-console warn --print-key]],
      [0,  %w[--log-console error --print-key]],
      [0,  %w[--log-console fatal --print-key]],
      [0,  %w[--log-console warn --log-console warn --print-key]],
      [64, %w[--log-console off --print-key]],
      [64, %w[--log-console off --quiet --print-key]],
      [64, %w[--log-console warn --log-console error --print-key]],
      [64, %w[--capture-logs --log-console off --log-console warn --print-key]],
      [64, %w[--log-console verbose --print-key]],
      [64, %w[--log-console OFF --capture-logs --print-key]],
      [64, %w[--log-console Warn --print-key]],
      [64, %w[--log-console --print-key]],
      [64, %w[--print-key --log-console]],
      [64, %w[--console --capture-logs --print-key]],
      [64, %w[--console --log-console warn --print-key]],
      [64, %w[--console --capture-logs --log-console off --print-key]],
    ].each do |want, args|
      it "exits #{want} for: selftest #{args.join(' ')}" do
        output, status = probe.run('selftest', *args)
        expect(status.exitstatus).to eq(want), "exited #{status.exitstatus}:\n#{output}"
      end
    end
  end

  describe '--only directories' do
    it 'rejects a tryouts directory with an actionable error' do
      output, status = probe.run('unit', '--only', 'try/unit/', '--print-key')

      expect(status.exitstatus).to eq(64), output
      expect(output).to include('pass individual *_try.rb files or run the full lane')
    end

    it 'rejects a tryouts directory through a symlinked checkout path' do
      Dir.mktmpdir('ots-lane-symlink') do |dir|
        checkout = File.join(dir, 'checkout')
        File.symlink(probe.repo_root, checkout)
        output, status = probe.run(
          'unit', '--only', 'apps/web/auth/try', '--print-key',
          runner_path: File.join(checkout, 'tests', 'lanes', 'run'),
          working_directory: checkout,
        )

        expect(status.exitstatus).to eq(64), output
        expect(output).to include('pass individual *_try.rb files or run the full lane')
      end
    end
  end

  describe '--quiet' do
    # The flag exports one name (hermetic_boundary_spec.rb reads it in the
    # task process) and chooses no formatter itself: the flags are put
    # together per rspec command line by tests/lanes/support/rspec_format.rb
    # (rspec_format_spec.rb), beside the JSON formatter.
    it 'asks for the quiet console formatter and derives no rspec flag' do
      output, status = probe.run('selftest', '--quiet', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'rspec_console')).to eq('quiet')
      expect(output).not_to include('--format')
      expect(output).not_to include('spec_opts')
    end

    # It used to exit 64 here: the formatter went into SPEC_OPTS, which
    # replaced the JSON formatter the results file depends on (#4683).
    it 'works beside RSPEC_OUTPUT_FILE' do
      output, status = probe.run('selftest', '--quiet', '--print-key',
                                 env: { 'RSPEC_OUTPUT_FILE' => 'tmp/argument-handling-results.json' })
      expect(status).to be_success, output
      expect(output).not_to include('cannot be honored')
      expect(probe.field(output, 'rspec_console')).to eq('quiet')
    end

    it 'works beside RSPEC_OUTPUT_FILE for an --only run too' do
      output, status = probe.run('selftest', '--quiet', '--print-key',
                                 '--only', 'spec/unit/lanes/hermetic_boundary_spec.rb',
                                 env: { 'RSPEC_OUTPUT_FILE' => 'tmp/argument-handling-results.json' })
      expect(status).to be_success, output
      expect(probe.field(output, 'rspec_console')).to eq('quiet')
    end
  end

  describe '--capture-logs and --log-console' do
    # What the flags derive, read back through --print-key. That they reach
    # the task process as exported names, and that nothing the caller
    # exported does, is hermetic_boundary_spec.rb; the files themselves are
    # capture_logs_spec.rb.
    let(:run_dir) { File.join(probe.repo_root, 'tmp', 'lanes', 'selftest', 'base') }

    it 'selects neither a log file nor a console setting without the flags' do
      output, status = probe.run('selftest', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'app_log')).to eq('none')
      expect(probe.field(output, 'mail_log')).to eq('none')
      expect(probe.field(output, 'log_console')).to start_with('none ')
      expect(probe.field(output, 'rspec_console')).to eq('none')
    end

    # CI's flags (.github/actions/run-test-lane) have to coexist with the
    # results file it asks for, with and without --quiet.
    it 'works beside RSPEC_OUTPUT_FILE and derives no rspec flag' do
      [[], %w[--quiet]].each do |quiet|
        output, status = probe.run('selftest', '--capture-logs', '--log-console', 'off', *quiet, '--print-key',
                                   env: { 'RSPEC_OUTPUT_FILE' => 'tmp/argument-handling-results.json' })
        expect(status).to be_success, output
        expect(output).not_to include('--format')
        expect(probe.field(output, 'log_console')).to start_with('off ')
        expect(probe.field(output, 'log_level')).to start_with('none ')
        expect(probe.field(output, 'rspec_console')).to eq(quiet.empty? ? 'none' : 'quiet')
      end
    end

    it 'puts app.log and mail.log in the run directory, as absolute paths' do
      output, status = probe.run('selftest', '--capture-logs', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'app_log')).to eq(File.join(run_dir, 'app.log'))
      expect(probe.field(output, 'mail_log')).to eq(File.join(run_dir, 'mail.log'))
      expect(probe.field(output, 'log_console')).to start_with('none ')
    end

    it 'keys the log files by overlay set, like the status file' do
      output, status = probe.run('selftest', '--overlay', 'billing', '--capture-logs', '--print-key')
      # selftest is a simple-mode lane and billing needs full mode, but that
      # check sits below --print-key: the derivation is what is read here.
      expect(status).to be_success, output
      expect(probe.field(output, 'app_log')).to end_with('/tmp/lanes/selftest/billing/app.log')
      expect(probe.field(output, 'mail_log')).to end_with('/tmp/lanes/selftest/billing/mail.log')
    end

    it 'gives an --only run the same files' do
      output, status = probe.run('selftest', '--capture-logs', '--log-console', 'off', '--print-key',
                                 '--only', 'spec/unit/lanes/hermetic_boundary_spec.rb')
      expect(status).to be_success, output
      expect(probe.field(output, 'app_log')).to eq(File.join(run_dir, 'app.log'))
      expect(probe.field(output, 'log_console')).to start_with('off ')
    end

    it 'passes the console setting through as given' do
      %w[trace debug info warn error fatal].each do |level|
        output, status = probe.run('selftest', '--log-console', level, '--print-key')
        expect(status).to be_success, output
        expect(probe.field(output, 'log_console')).to start_with("#{level} ")
        expect(probe.field(output, 'app_log')).to eq('none')
      end
    end

    it 'says why --log-console off needs a log file' do
      output, status = probe.run('selftest', '--log-console', 'off', '--print-key')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('--log-console off needs --capture-logs')
    end

    it 'names the accepted values when the value is not one of them' do
      output, status = probe.run('selftest', '--log-console', 'verbose', '--print-key')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('trace debug info warn error fatal')
    end

    it 'marks the quiet console formatter under --quiet' do
      output, status = probe.run('selftest', '--quiet', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'rspec_console')).to eq('quiet')
    end

    # The four names are the runner's to assign. A lane env file or an
    # overlay is sourced below the scrub, so it could set one where the
    # caller's shell cannot; the runner refuses the run instead of writing
    # to a path it never created or dropping the line without a word.
    %w[LANES_APP_LOG_FILE LANES_MAIL_LOG_FILE LANES_APP_LOG_CONSOLE LANES_RSPEC_CONSOLE].each do |name|
      it "refuses an overlay that sets #{name}" do
        probe.with_overlay("#{name}=/tmp/overlay-chosen\n") do |overlay|
          [[], %w[--capture-logs --log-console off --quiet]].each do |flags|
            output, status = probe.run('selftest', '--overlay', overlay, *flags, '--print-key')
            expect(status.exitstatus).to eq(64), output
            expect(output).to include("#{name} is assigned by the runner")
            expect(output).not_to include('app_log=')
          end
        end
      end
    end
  end

  describe 'without a lane named' do
    # --which answers from the ownership table alone; a lane-less --only
    # infers from it (exact single owner, or exit 64 naming the candidates);
    # a lane given anywhere but first, or spelled as a path, is refused.
    [
      [0,  %w[--which spec/api]],
      [0,  %w[--which tests/browser/saml_callback_spec.rb]],
      [0,  %w[--which lib/onetime.rb]],
      [64, %w[--which docs]],
      [64, %w[--which]],
      [64, %w[--which spec/api lib]],
      [0,  %w[--only spec/unit/lanes/hermetic_boundary_spec.rb --print-key]],
      [0,  %w[--only tests/browser/saml_callback_spec.rb --print-key]],
      [0,  %w[--only spec/unit/lanes --print-key]],
      [64, %w[--only try/unit --print-key]],
      [64, %w[--only apps/web/billing/try --print-key]],
      [0,  %w[--quiet --only spec/unit/lanes/hermetic_boundary_spec.rb --only spec/unit/lanes/run_all_spec.rb --print-key]],
      [64, %w[--only spec/integration/full --print-key]],
      [64, %w[--only spec/unit/lanes/hermetic_boundary_spec.rb --only spec/api --print-key]],
      [64, %w[--only README.md --print-key]],
      [64, %w[--print-key]],
      [64, %w[--quiet]],
      [64, %w[--console --print-key]],
      [64, %w[selftest --which spec/api]],
      [64, %w[../selftest --print-key]],
      [64, %w[selftest/ --print-key]],
      [64, %w[../../tests/lanes/selftest --print-key]],
    ].each do |want, args|
      it "exits #{want} for: #{args.join(' ')}" do
        output, status = probe.run(*args)
        expect(status.exitstatus).to eq(want), "exited #{status.exitstatus}:\n#{output}"
      end
    end

    it 'prints exactly the owning lane for --which on a single-owner path' do
      output, status = probe.run('--which', 'spec/api')
      expect(status).to be_success, output
      expect(output.lines.grep_v(/\Anote:/).map(&:chomp)).to eq(['api'])
    end

    it 'lists every owner for --which on a shared integration tree' do
      output, status = probe.run('--which', 'spec/integration/full')
      expect(status).to be_success, output
      expect(output.lines.grep_v(/\Anote:/).map(&:chomp)).to eq(%w[full-sqlite full-pg full-pg-agnostic])
    end

    it 'infers the lane for a lane-less --only with one owner' do
      output, status = probe.run('--only', 'spec/unit/lanes/hermetic_boundary_spec.rb', '--print-key')
      expect(status).to be_success, output
      expect(output).to include('[lane:unit] inferred from --only')
      expect(probe.field(output, 'lane').split.first).to eq('unit')
    end

    it 'names the candidates when a lane-less --only is ambiguous' do
      output, status = probe.run('--only', 'spec/integration/full', '--print-key')
      expect(status.exitstatus).to eq(64), output
      expect(output).to match(/full-sqlite.*full-pg.*full-pg-agnostic/m)
    end
  end
end
