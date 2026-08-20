# spec/unit/lanes/codegen_phase_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# Regression harness for the runner-owned codegen phase in tests/lanes/run.
#
# The rule the phase encodes: a lane declares WHAT it needs generated
# (LANES_CODEGEN in its env file) and the runner decides WHETHER to run it.
# Two ways to get that wrong, both silent:
#
#   - the phase stops running by default, and a lane's specs then read
#     whatever stale generated/ the last run left behind (or, with an empty
#     generated/locales, spec_helper aborts the whole suite);
#   - `--skip-codegen` stops being honored, and the parallel runner that
#     generates once and fans out has every child rewriting one shared,
#     non-atomically-written directory underneath the others.
#
# Method: run the real runner against the `selftest` lane, which needs no
# services and finishes in milliseconds, with a codegen declaration injected
# through BASH_ENV. `selftest` is the one lane that declares no codegen of
# its own, so nothing has to be edited for the injection to take — and the
# injected token is deliberately not one the runner knows, which turns "the
# phase ran" into a fast, unambiguous exit 64 instead of a two-second
# generator invocation with output to parse.
module LaneCodegenProbe
  BOGUS_TOKEN = 'ots-lane-codegen-probe-token'

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

  # A lane declaration is an ordinary exported variable by the time the
  # runner reads it (`set -a` + `source <lane>/env`), so a readonly export
  # the scrub cannot clear is a faithful stand-in for one — and the only
  # way to write this example without inventing a fixture lane. Same
  # BASH_ENV mechanism hermetic_boundary_spec.rb uses for readonly
  # functions.
  def run_selftest(*args, env: {})
    Dir.mktmpdir('ots-lane-codegen') do |dir|
      rc = File.join(dir, 'declare.bash')
      File.write(rc, "export LANES_CODEGEN='#{BOGUS_TOKEN}'\nreadonly LANES_CODEGEN\n")
      Open3.capture2e(
        { 'BASH_ENV' => rc, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
        runner, 'selftest', *args, chdir: repo_root
      )
    end
  end

  # The phase announces each token before running it, and rejects one it
  # does not recognize. Either is proof it executed.
  def phase_ran?(output)
    output.include?("codegen: #{BOGUS_TOKEN}")
  end
end

RSpec.describe 'tests/lanes/run codegen phase' do
  let(:probe) { LaneCodegenProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'runs the declared codegen on a direct lane invocation' do
    # The default has to be "generate". A direct run is what a developer
    # types before pushing, and it is the only thing standing between a
    # stale generated/ and a green lane that means nothing.
    output, status = probe.run_selftest

    expect(probe.phase_ran?(output)).to be(true), "codegen phase did not run:\n#{output}"
    expect(status.exitstatus).to eq(64)
    expect(output).to include("unknown codegen token '#{LaneCodegenProbe::BOGUS_TOKEN}'")
  end

  it 'skips the phase for --skip-codegen' do
    output, status = probe.run_selftest('--skip-codegen')

    expect(probe.phase_ran?(output)).to be(false), "codegen phase ran despite --skip-codegen:\n#{output}"
    expect(status).to be_success
    expect(output).to include('--- lane:selftest end ---')
  end

  it 'skips the phase for --only, as it always has' do
    # --only bypasses the tasks file wholesale, and the codegen lines used
    # to live in that file — so this is not a new rule, it is the old one
    # surviving the move into the runner. Two --only paths of different
    # kinds make the runner refuse for an unrelated reason a few lines
    # later, which is what proves the phase was passed over rather than
    # merely quiet.
    output, status = probe.run_selftest(
      '--only', 'try/unit/base_view_try.rb',
      '--only', 'spec/unit/lanes/hermetic_boundary_spec.rb',
    )

    expect(probe.phase_ran?(output)).to be(false), "codegen phase ran despite --only:\n#{output}"
    expect(status.exitstatus).to eq(64)
    expect(output).to include('--only cannot mix tryouts')
  end

  it 'does not let the calling shell turn the phase off' do
    # The flag is runner-internal state, assigned below the scrub and never
    # read from the environment. A dev shell that exports the name it would
    # plausibly be called must not be able to switch generation off for
    # every lane run started from that shell.
    output, = probe.run_selftest(env: { 'SKIP_CODEGEN' => '1', 'LANES_SKIP_CODEGEN' => '1' })

    expect(probe.phase_ran?(output)).to be(true), "an exported flag suppressed the phase:\n#{output}"
  end

  describe 'lane declarations' do
    # The phase is only as good as what the lanes declare, and a lane whose
    # tasks file still carries its own generator line would generate twice
    # (or, once run-all passes --skip-codegen, exactly when it was told not
    # to). Cheap to state as a fact about the files.
    lanes_dir = File.expand_path('../../../tests/lanes', __dir__)

    Dir.children(lanes_dir).select { |d| File.file?(File.join(lanes_dir, d, 'tasks')) }.sort.each do |lane|
      it "keeps generator commands out of the #{lane} lane's tasks file" do
        tasks = File.read(File.join(lanes_dir, lane, 'tasks'))
        commands = tasks.lines.grep_v(/\A\s*(#|\z)/).join

        expect(commands).not_to match(/locales:sync|schemas:json:generate|i18n content compile/)
      end
    end

    it 'declares only tokens the runner knows' do
      known = %w[locales locales-python schemas]

      Dir.children(lanes_dir).sort.each do |lane|
        env_file = File.join(lanes_dir, lane, 'env')
        next unless File.file?(env_file)

        declared = File.read(env_file)[/^LANES_CODEGEN=['"]?([^'"\n]*)/, 1].to_s.split
        expect(declared - known).to be_empty, "lane '#{lane}' declares unknown codegen tokens"
      end
    end
  end
end
