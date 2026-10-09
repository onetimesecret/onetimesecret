# spec/unit/lanes/argument_handling_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/lane_probe'
require 'fileutils'
require 'open3'
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
  extend LaneProbe

  module_function

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
end

RSpec.describe 'tests/lanes/run argument handling' do
  let(:probe) { LaneArgumentProbe }

  include_context 'with the lane runner bash'

  describe 'with a lane named' do
    # `<expected exit>, <argv after the lane>`. A flag set whose derivation
    # an example further down reads back is not repeated here.
    [
      [0,  %w[--print-key]],
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
      [0,  %w[--capture-logs --log-console error --print-key]],
      [0,  %w[--log-console warn --log-console warn --print-key]],
      [64, %w[--log-console off --quiet --print-key]],
      [64, %w[--log-console warn --log-console error --print-key]],
      [64, %w[--capture-logs --log-console off --log-console warn --print-key]],
      [64, %w[--log-console OFF --capture-logs --print-key]],
      [64, %w[--log-console Warn --print-key]],
      [64, %w[--log-console --print-key]],
      [64, %w[--print-key --log-console]],
      [64, %w[--console --capture-logs --print-key]],
      [64, %w[--console --log-console warn --print-key]],
      [64, %w[--console --capture-logs --log-console off --print-key]],
      [0,  %w[--workers 1 --print-key]],
      [0,  %w[--workers 64 --print-key]],
      [64, %w[--workers 0 --print-key]],
      [64, %w[--workers x --print-key]],
      [64, %w[--workers 65 --print-key]],
      [64, %w[--workers -1 --print-key]],
      [64, %w[--workers --print-key]],
      [64, %w[--print-key --workers]],
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
      expect(output).to include('individual *_try.rb files')
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
        expect(output).to include('individual *_try.rb files')
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
    # results file it asks for, with and without --quiet. --quiet used to
    # exit 64 beside it: the formatter went into SPEC_OPTS, which replaced
    # the JSON formatter the results file depends on (#4683).
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

  describe '--workers' do
    # The count a lane's tasks fan out over (#4551). The lane env file sets
    # the default (LANES_WORKERS, part of the workload the lane defines, so
    # an overlay may set it too); the flag overrides it; the runner's own
    # record of the flag (WORKERS_OVERRIDE) is refused from a file like every
    # other flag. What the count derives is isolation_key_spec.rb.
    it 'defaults to one worker when neither the lane nor the flag says otherwise' do
      output, status = probe.run('selftest', '--print-key')
      expect(status).to be_success, output
      expect(output).to include(' workers=1 ')
    end

    it 'takes the lane\'s LANES_WORKERS default and lets --workers override it' do
      probe.with_overlay("LANES_WORKERS=3\n") do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, '--print-key')
        expect(status).to be_success, output
        expect(output).to include(' workers=3 ')

        output, status = probe.run('selftest', '--overlay', overlay, '--workers', '2', '--print-key')
        expect(status).to be_success, output
        expect(output).to include(' workers=2 ')
      end
    end

    it 'validates a LANES_WORKERS from a file like the flag' do
      # An empty value reads as unset (one worker), like an absent line.
      %w[0 65 four].each do |value|
        probe.with_overlay("LANES_WORKERS='#{value}'\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')
          expect(status.exitstatus).to eq(64), "LANES_WORKERS=#{value.inspect} exited #{status.exitstatus}:\n#{output}"
          expect(output).to include('LANES_WORKERS must be')
        end
      end
    end

    it 'runs one worker for --only and --console whatever was asked' do
      output, status = probe.run('unit', '--workers', '4', '--only', 'spec/unit/lanes/hermetic_boundary_spec.rb',
                                 '--print-key')
      expect(status).to be_success, output
      expect(output).to include(' workers=1 ')

      output, status = probe.run('unit', '--workers', '4', '--console', '--print-key')
      expect(status).to be_success, output
      expect(output).to include(' workers=1 ')
    end

    it 'refuses more than one worker for the smoke lane' do
      output, status = probe.run('smoke', '--workers', '2', '--print-key')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('smoke lane runs one command')
      expect(output).not_to include('lane=smoke')
    end

    it 'refuses more than one worker for a Postgres-backed lane, and accepts one' do
      %w[full-pg full-pg-agnostic migrations-pg].each do |lane|
        output, status = probe.run(lane, '--workers', '2', '--print-key')
        expect(status.exitstatus).to eq(64), "#{lane}:\n#{output}"
        expect(output).to include('Postgres-backed lane')
      end
      output, status = probe.run('full-pg', '--workers', '1', '--print-key')
      expect(status).to be_success, output
    end

    it 'names the count and the flag in --help' do
      output, status = probe.run('--list')
      expect(status).to be_success, output
      expect(output).to include('--workers <n>')
    end
  end

  # A lane env file or overlay runs in the runner's own shell. The flag
  # state the argument parser filled in is the runner's: an overlay line such
  # as `LOG_CONSOLE=warn` would otherwise hold the console to warn with no
  # flag on the command line, `LOG_CONSOLE=off` would skip the check that
  # off needs a log file, and `CAPTURE_LOGS=1` would turn capture on.
  describe 'an overlay that sets the runner\'s own state' do
    {
      'QUIET' => ['1', '--quiet'],
      'CAPTURE_LOGS' => ['1', '--capture-logs'],
      'LOG_CONSOLE' => ['warn', '--log-console'],
      'SKIP_CODEGEN' => ['1', '--skip-codegen'],
      'PRINT_KEY' => ['1', '--print-key'],
      'CONSOLE' => ['1', '--console'],
      'WORKERS_OVERRIDE' => ['2', '--workers'],
      'PASSTHROUGH' => ['1', '-- <rspec args>'],
    }.each do |name, (value, flag)|
      it "refuses #{name}=#{value} and names #{flag}" do
        probe.with_overlay("#{name}=#{value}\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status.exitstatus).to eq(64), output
          expect(output).to include("#{overlay}.env sets #{name}")
          expect(output).to include(flag)
          expect(output).not_to include('lane=selftest')
        end
      end
    end

    it 'refuses LOG_CONSOLE=off, which would skip the check that off needs a log file' do
      probe.with_overlay("LOG_CONSOLE=off\n") do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

        expect(status.exitstatus).to eq(64), output
        expect(output).to include('sets LOG_CONSOLE')
        expect(output).not_to include('log_console=off')
      end
    end

    # Same value, but sourced under allexport: the name would be exported to
    # every task of the run.
    it 'refuses a line that assigns the value the variable already has' do
      probe.with_overlay("QUIET=0\n") do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

        expect(status.exitstatus).to eq(64), output
        expect(output).to include('sets QUIET')
      end
    end

    it 'refuses a line that unsets one' do
      probe.with_overlay("unset CAPTURE_LOGS\n") do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

        expect(status.exitstatus).to eq(64), output
        expect(output).to include('sets CAPTURE_LOGS')
      end
    end

    %w[LANE REPO_ROOT OVERLAY_KEY].each do |name|
      it "refuses #{name}, which no flag sets" do
        probe.with_overlay("#{name}=elsewhere\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status.exitstatus).to eq(64), output
          expect(output).to include("sets #{name}", 'which lane or checkout')
        end
      end
    end

    # The overlay is sourced inside the runner's loop over --overlay names,
    # and bash applies a `break` or `continue` in a sourced file to that
    # loop. Either one would skip the refusal above and leave allexport on.
    %w[break continue].each do |word|
      it "refuses an overlay that leaves the runner's loop with #{word}, whatever it set first" do
        probe.with_overlay("QUIET=1\n#{word}\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status.exitstatus).to eq(64), output
          expect(output).to include('break or continue')
          expect(output).not_to include('lane=selftest')
        end
      end
    end

    it 'leaves an overlay that sets its own variables alone, with every flag' do
      probe.with_overlay("ARGUMENT_HANDLING_SPEC_SETTING=1\nLANES_DATASTORE_DB=7\n") do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, '--capture-logs', '--log-console', 'off',
                                   '--quiet', '--print-key')

        expect(status).to be_success, output
        expect(output).to include("lane=selftest overlays=#{overlay} db=7")
        expect(probe.field(output, 'log_console')).to start_with('off ')
      end
    end

    # The files are sourced at the top level of the runner. Sourced inside a
    # function, a `declare` or `typeset` line would make a variable local to
    # that function: gone on return, never exported, and nothing printed.
    # This one runs the selftest tasks, which print the environment they got.
    it 'hands the tasks a variable an overlay assigns with declare or typeset' do
      overlay_lines = <<~ENV
        declare -x ARGUMENT_HANDLING_SPEC_DECLARE_X=one
        declare ARGUMENT_HANDLING_SPEC_DECLARE=two
        typeset ARGUMENT_HANDLING_SPEC_TYPESET=three
        ARGUMENT_HANDLING_SPEC_PLAIN=four
      ENV

      probe.with_overlay(overlay_lines) do |overlay|
        output, status = probe.run('selftest', '--overlay', overlay, env: { 'CI' => nil })

        expect(status).to be_success, output
        expect(output.lines.map(&:chomp)).to include(
          'ARGUMENT_HANDLING_SPEC_DECLARE_X=one', 'ARGUMENT_HANDLING_SPEC_DECLARE=two',
          'ARGUMENT_HANDLING_SPEC_TYPESET=three', 'ARGUMENT_HANDLING_SPEC_PLAIN=four'
        )
      ensure
        FileUtils.rm_rf(File.join(probe.repo_root, 'tmp', 'lanes', 'selftest', overlay))
      end
    end

    ['declare QUIET=1', 'declare -x CAPTURE_LOGS=1', 'typeset LOG_CONSOLE=warn'].each do |line|
      it "refuses the runner's own state assigned with a declaration: #{line}" do
        probe.with_overlay("#{line}\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status.exitstatus).to eq(64), output
          expect(output).to include("runner's own state")
          expect(output).not_to include('lane=selftest')
        end
      end
    end
  end

  # rspec reads SPEC_OPTS after the command line, and a formatter there
  # replaces every formatter the run chose, the JSON results one included:
  # the run would write no results and report nothing wrong. The caller's
  # SPEC_OPTS is scrubbed; an env file is the one place left to set it.
  describe 'an overlay that sets SPEC_OPTS' do
    ['--format documentation', '--format=json', '-f d', '-fd', '--seed 1 --out results.txt', '-o results.txt',
     '--seed 1 -fp',].each do |opts|
      it "refuses a formatter or its output file: #{opts}" do
        probe.with_overlay("SPEC_OPTS='#{opts}'\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status.exitstatus).to eq(64), output
          expect(output).to include('selects an rspec formatter')
          expect(output).not_to include('lane=selftest')
        end
      end
    end

    ['--seed 1234', '--fail-fast', '--order defined --only-failures', '--force-color'].each do |opts|
      it "accepts options that select no formatter: #{opts}" do
        probe.with_overlay("SPEC_OPTS='#{opts}'\n") do |overlay|
          output, status = probe.run('selftest', '--overlay', overlay, '--print-key')

          expect(status).to be_success, output
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
      expect(output).to include('[lane:harness] inferred from --only')
      expect(probe.field(output, 'lane').split.first).to eq('harness')
    end

    it 'names the candidates when a lane-less --only is ambiguous' do
      output, status = probe.run('--only', 'spec/integration/full', '--print-key')
      expect(status.exitstatus).to eq(64), output
      expect(output).to match(/full-sqlite.*full-pg.*full-pg-agnostic/m)
    end
  end
end
