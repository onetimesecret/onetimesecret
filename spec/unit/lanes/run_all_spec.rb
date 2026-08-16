# spec/unit/lanes/run_all_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Guard rails for tests/lanes/run-all, the fan-out wrapper over
# tests/lanes/run. Everything here exercises the wrapper's fail-fast
# surface — argument validation, the duplicate-lane guard, the parallel
# preconditions and the dry-run plan — none of which starts a lane or
# touches a service, so the whole file finishes in well under a second.
#
# What is deliberately NOT here: a real fan-out. Running two lanes end to
# end is minutes of wall clock and belongs in a developer's terminal, not
# in spec:fast; the pieces a real run composes (isolation key, owner
# marker, liveness token, codegen phase) each have their own spec next to
# this one.
module LaneRunAllProbe
  module_function

  def repo_root
    File.expand_path('../../..', __dir__)
  end

  def wrapper
    File.join(repo_root, 'tests', 'lanes', 'run-all')
  end

  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(repo_root, '.bash-version')).strip)
  end

  def path_bash_major
    return @path_bash_major if defined?(@path_bash_major)

    out, status = Open3.capture2e('bash', '-c', 'echo "${BASH_VERSINFO[0]}"')
    @path_bash_major = status.success? ? Integer(out.strip, exception: false) : nil
  end

  # CI is scrubbed to nil by default: the wrapper reads it for the
  # --parallel guard, and this spec itself runs under CI — the example
  # that asserts on that guard sets it explicitly instead of inheriting
  # whatever the harness happens to carry.
  def run(*args, env: {})
    Open3.capture2e({ 'CI' => nil }.merge(env), wrapper, *args, chdir: repo_root)
  end

  def run_with_readonly_codegen(*args)
    # A readonly exported name cannot be removed with `unset`, which is the
    # hostile caller state the wrapper must not inherit while reading lane env.
    Open3.capture2e(
      { 'CI' => nil },
      'bash',
      '-c',
      'readonly LANES_CODEGEN=schemas; export LANES_CODEGEN; exec "$@"',
      'bash',
      wrapper,
      *args,
      chdir: repo_root,
    )
  end
end

RSpec.describe 'tests/lanes/run-all' do
  let(:probe) { LaneRunAllProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'prints usage for --help' do
    output, status = probe.run('--help')

    expect(status).to be_success
    expect(output).to include('usage: tests/lanes/run-all')
    expect(output).to include('--skip-codegen')
  end

  it 'rejects an unknown lane before starting anything' do
    output, status = probe.run('no-such-lane')

    expect(status.exitstatus).to eq(64)
    expect(output).to include("unknown lane 'no-such-lane'")
  end

  it 'rejects a duplicate lane before starting anything' do
    # Two runs of one lane derive the same isolation key, so they would
    # share a valkey index and a PG database. tests/lanes/run detects the
    # collision too, but only once it is far enough in to have claimed the
    # liveness token; a duplicate in argv is a typo, and argv parsing is
    # where a typo is cheapest to report.
    output, status = probe.run('unit', 'simple', 'unit')

    expect(status.exitstatus).to eq(64)
    expect(output).to include("lane 'unit' given twice")
  end

  it 'refuses to run the smoke lane in parallel' do
    # pnpm test:smoke regenerates locales inside `pnpm test` no matter what
    # --skip-codegen says, into the one repo-root generated/ directory the
    # other lanes read from mid-run.
    output, status = probe.run('--parallel', 'smoke', 'unit')

    expect(status.exitstatus).to eq(64)
    expect(output).to include('smoke lane cannot run in parallel')
  end

  it 'refuses --parallel under CI' do
    # CI pins every lane to datastore index 0 (the CI branch in
    # tests/lanes/run), so parallel lanes there would share one datastore —
    # the exact contamination --parallel depends on not having.
    output, status = probe.run('--parallel', '--dry-run', 'unit', 'simple', env: { 'CI' => '1' })

    expect(status.exitstatus).to eq(64)
    expect(output).to include('--parallel with CI set')
  end

  describe '--dry-run' do
    it 'plans the default set: one codegen union, every child --skip-codegen' do
      output, status = probe.run('--dry-run')

      expect(status).to be_success
      expect(output).to include('lanes:   unit simple disabled full-sqlite')
      # The union of what the four lanes declare, generated once up front …
      expect(output).to include('codegen: locales schemas')
      # … and every child told so. A planned child without the flag is a
      # child that will regenerate into the shared generated/ mid-fan-out.
      %w[unit simple disabled full-sqlite].each do |lane|
        expect(output).to include("tests/lanes/run #{lane} --skip-codegen")
      end
      expect(output).not_to include('tests/lanes/run smoke')
    end

    it 'does not read lane declarations from the calling environment' do
      # selftest declares no codegen and blanks its service URLs, so caller
      # values must not fill either back in.
      output, status = probe.run(
        '--dry-run', 'selftest',
        env: {
          'LANES_CODEGEN' => 'schemas',
          'AUTH_DATABASE_URL' => 'postgresql://x:y@127.0.0.1:2154/leak',
        },
      )

      expect(status).to be_success
      expect(output).to include('codegen: none')
      expect(output).to include('ports:   none')
    end

    it 'does not read readonly exported lane declarations' do
      output, status = probe.run_with_readonly_codegen('--dry-run', 'selftest')

      expect(status).to be_success
      expect(output).to include('codegen: none')
      expect(output).to include('ports:   none')
    end
  end

  it 'knows exactly the codegen tokens the runner knows' do
    # The wrapper duplicates the runner's token -> command mapping because
    # the runner has no codegen-only entry point to delegate to. This pins
    # the two case statements to the same token set, so a token added to
    # one without the other fails here instead of as a silently skipped
    # prerequisite in a fan-out.
    tokens = ->(path) { File.read(path).scan(/^\s*(locales|locales-python|schemas)\)\s*$/).flatten.sort }
    runner_tokens  = tokens.call(File.join(probe.repo_root, 'tests', 'lanes', 'run'))
    wrapper_tokens = tokens.call(probe.wrapper)

    expect(runner_tokens).to eq(%w[locales locales-python schemas])
    expect(wrapper_tokens).to eq(runner_tokens)
  end
end
