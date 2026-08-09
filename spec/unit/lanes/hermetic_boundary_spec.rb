# spec/unit/lanes/hermetic_boundary_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# Regression harness for the hermetic boundary in tests/lanes/run.
#
# The scrub block is what stands between a dev shell's REDIS_URL and the
# developer's own Valkey data, and it is subtle enough that its last defect
# — an awk filter matching the literal attribute string `-fx`, which let
# every `-ftx`/`-frx` exported function through — was caught by human
# review rather than by a test. This spec is what makes the next one fail.
#
# Method: run the real `tests/lanes/run selftest` from a deliberately
# poisoned parent environment and assert on what the task process actually
# received. The `selftest` lane exists only for this — it blanks the three
# service URLs so the preflight needs no ports, runs no application code,
# and prints its environment between markers.
#
# The traced-function case is built with BASH_ENV rather than `export -f`
# plus `declare -ft`, because function attributes are not preserved across
# exec: a traced function exported to a child arrives there as plain `-fx`.
# BASH_ENV is sourced by the runner's OWN shell before line one of the
# script, so `declare -ft` there produces the `-ftx` attribute set inside
# the process doing the scrubbing — the exact shape the old filter missed.
# It doubles as a check that BASH_ENV is itself scrubbed, so the task
# process does not re-source it.
module LaneHermeticProbe
  # Distinctive enough that finding it anywhere in the child's environment
  # is unambiguous evidence of a leak.
  CANARY    = 'lane-selftest-canary-8f3a1c'
  # Distinct from CANARY: the keep-listed names are supposed to arrive, so
  # their value must not be the string the leak assertions scan for.
  KEEPSAKE  = 'lane-selftest-keepsake-2b7d40'
  PLAIN_FN  = 'lane_selftest_plain_fn'
  TRACED_FN = 'lane_selftest_traced_fn'
  # Readonly shapes: `unset`/`unset -f` fail on these, so they survive the
  # scrub inside the runner's shell and must be stripped at the exec
  # boundary instead.
  RO_FN     = 'lane_selftest_readonly_fn'
  RO_VAR    = 'LANE_SELFTEST_READONLY_VAR'
  # A function named after the tool the scrub itself used to shell out to.
  # Bash resolves functions before commands, so this one *was* the filter
  # that decided which functions got scrubbed.
  TOOL_FN   = 'awk'
  # The same hazard one stage later. The exec-boundary strip runs *after* the
  # function scrub, so a plain exported function is already gone by then and
  # only a readonly one is still live to shadow the `env` that enumerates
  # non-identifier names. Readonly-ness is not preserved across exec, which
  # is why this one has to come in through BASH_ENV like RO_FN.
  RO_TOOL_FN = 'env'
  # Environment entries whose names are not valid shell identifiers. execve
  # accepts them, `compgen -e` does not enumerate them, and `unset` cannot
  # clear them — they can only leave at the exec boundary.
  ODD_NAMES = ['FOO-BAR', 'ORGS.SSO'].freeze

  module_function

  def repo_root
    File.expand_path('../../..', __dir__)
  end

  # The floor the runner enforces, read from the same pin file it reads —
  # a literal here would be a third copy of the number (runner, doctor,
  # spec) and the first one to go stale silently skips this whole file.
  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(repo_root, '.bash-version')).strip)
  end

  # The runner's shebang is `#!/usr/bin/env bash`, so the bash that matters
  # is the first one on PATH — not the shell that launched RSpec, and on
  # macOS not /bin/bash either.
  def path_bash_major
    return @path_bash_major if defined?(@path_bash_major)

    out, status = Open3.capture2e('bash', '-c', 'echo "${BASH_VERSINFO[0]}"')
    @path_bash_major = status.success? ? Integer(out.strip, exception: false) : nil
  end

  # Every name here is either a variable that must not survive, or one
  # whose lane-supplied value must win over the caller's.
  def poisoned_env(bash_env_path)
    {
      # The "tests wiped my dev database" case: canonical dev ports.
      'REDIS_URL' => 'redis://127.0.0.1:6379/0',
      'AUTH_DATABASE_URL' => "postgres://127.0.0.1:5432/#{CANARY}",
      # Ordinary application variables, the class that has leaked before
      # (PG*, ORGS_*, CUSTOM_MAIL_*, BRAND_*).
      'ORGS_SSO_ENABLED' => 'true',
      'OTS_LANE_LEAK_CANARY' => CANARY,
      # Determinism pins the lane must override rather than inherit.
      'NODE_ENV' => 'development',
      'TZ' => 'America/Toronto',
      'LANG' => 'en_US.ISO8859-1',
      'LC_ALL' => 'en_US.ISO8859-1',
      # Keep-listed: these must arrive intact, sentinel value and all.
      'CI' => KEEPSAKE,
      'COVERAGE' => KEEPSAKE,
      # Keep-listed, and load-bearing here: this spec must never start
      # containers, whatever the preflight concludes.
      'LANES_NO_AUTOSTART' => '1',
      # Turns on the runner's `[lane:scrub] unset ...` trace. Without it
      # the function assertions below are only negative, and a negative
      # assertion cannot tell "the scrub worked" from "the poison never
      # arrived" — if BASH_ENV ever stops being sourced by the runner's
      # own shell, every one of them passes for the wrong reason and the
      # regression this file exists to catch reopens in silence. The trace
      # is the positive half: it proves the functions were there to scrub.
      'LANES_DEBUG_ENV' => '1',
      'BASH_ENV' => bash_env_path,
      # The exact shape .github/actions/run-test-lane/action.yml produces:
      # it passes the lane and overlay as step env, so the runner inherits
      # them as exported names it also assigns to itself. An assignment
      # into an exported name keeps the export attribute, which once put
      # the runner's own `LANE` on the scrub list and aborted every CI job
      # at `${LANE}` under set -u. Poison them here so the ordering
      # invariant in tests/lanes/run stays enforced by a test.
      'LANE' => 'selftest',
      'OVERLAY' => '',
      # Bash imports an exported SHELLOPTS at startup, so this turns on
      # allexport inside the runner's own shell before line one — the
      # caller-ran-`set -a` case. The runner must reset the option before
      # its first assignment (or the scrub's working variables become
      # exported and get cleared mid-scrub), and SHELLOPTS itself is
      # readonly-exported, so it can only leave via the exec-boundary
      # strip.
      'SHELLOPTS' => 'allexport',
      # BASHOPTS is the shopt twin of SHELLOPTS: also imported at startup,
      # also readonly-exported, so it rides the same exec-boundary strip.
      # extdebug is the nastiest import — it changes function-return
      # semantics — which is exactly why the runner must shed it.
      #
      # nocasematch rides along because it silently rewrites the scrub's own
      # logic: it makes the keep-list `case` match without regard to case, so
      # the homograph names below (`ci`, `Path` — separate variables as far
      # as bash is concerned) would be treated as keep-listed and delivered.
      # `shopt -u` is the only way to shed either; `set +o` cannot see them.
      'BASHOPTS' => 'extdebug:nocasematch',
      'ci' => CANARY,
      'Path' => CANARY,
      'Home' => CANARY,
      'Coverage' => CANARY,
    }.merge(ODD_NAMES.to_h { |name| [name, CANARY] })
  end

  # Sourced by the runner's own shell at startup. Two exported functions
  # with different attribute sets: `-fx`, which the old filter caught, and
  # `-ftx`, which it did not.
  def bash_env_contents
    <<~RC
      #{PLAIN_FN}() { :; }
      export -f #{PLAIN_FN}
      #{TRACED_FN}() { :; }
      export -f #{TRACED_FN}
      declare -ft #{TRACED_FN}
      #{RO_FN}() { :; }
      export -f #{RO_FN}
      readonly -f #{RO_FN}
      export #{RO_VAR}=#{CANARY}
      readonly #{RO_VAR}
      #{TOOL_FN}() { :; }
      export -f #{TOOL_FN}
      #{RO_TOOL_FN}() { echo "#{CANARY}"; }
      export -f #{RO_TOOL_FN}
      readonly -f #{RO_TOOL_FN}
    RC
  end

  def section(output, from, to)
    start  = output.index("--- lane:selftest #{from} ---")
    finish = output.index("--- lane:selftest #{to} ---")
    raise "selftest markers missing (#{from}/#{to}) in:\n#{output}" unless start && finish

    output[start...finish].lines.drop(1)
  end

  # One subprocess for the whole file: the input is constant, and the lane
  # is deliberately cheap enough that this stays well under a second.
  def result
    @result ||= capture
  end

  def capture
    Dir.mktmpdir('ots-lane-selftest') do |dir|
      rc = File.join(dir, 'poison.bash')
      File.write(rc, bash_env_contents)

      runner = File.join(repo_root, 'tests', 'lanes', 'run')
      output, status = Open3.capture2e(poisoned_env(rc), runner, 'selftest', chdir: repo_root)

      env_lines = section(output, 'env', 'functions')
      # Values can span lines — a leaked function arrives as a multi-line
      # BASH_FUNC_name%% entry — so keep the raw lines for prefix scanning
      # and build the hash only from lines shaped `NAME=value`.
      pairs = env_lines.filter_map do |line|
        line.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\n?\z/) { |m| [m[1], m[2]] }
      end

      {
        status: status,
        output: output,
        # Everything the TASK process printed, and nothing the runner
        # printed on its way there. The scrub trace names each variable
        # and function it clears, so a whole-capture `not_to include` on
        # a name is unsatisfiable once tracing is on — and the trace is
        # what makes the tracing worth having. Scope name-based negatives
        # to this; value-based ones can stay on the whole capture,
        # because the trace prints names only, never values.
        task_output: section(output, 'env', 'end').join,
        # Lines the runner's scrub emitted on stderr, merged into the
        # capture by capture2e. This is the positive evidence that the
        # poisoned environment reached the process doing the scrubbing.
        scrub_trace: output.lines.grep(/\A\[lane:scrub\] /).map(&:chomp),
        env: pairs.to_h,
        env_lines: env_lines,
        functions: section(output, 'functions', 'end').map { |line| line.split.last },
      }
    end
  end
end

RSpec.describe 'tests/lanes/run hermetic boundary' do
  let(:probe)  { LaneHermeticProbe }
  let(:result) { probe.result }
  let(:env)    { result[:env] }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'runs the selftest lane without services' do
    expect(result[:status]).to be_success, "tests/lanes/run selftest failed:\n#{result[:output]}"
  end

  it 'does not let a dev-shell service URL reach the task process' do
    # Blank rather than absent: the lane's env pins these empty so the
    # preflight needs no ports. What matters is that the canonical dev
    # endpoints are nowhere in the environment the tasks got.
    expect(env['REDIS_URL']).to eq('')
    expect(env['AUTH_DATABASE_URL']).to eq('')
    expect(result[:output]).not_to include('redis://127.0.0.1:6379/0')
    expect(result[:output]).not_to include('127.0.0.1:5432')
  end

  it 'does not let an arbitrary application variable reach the task process' do
    expect(env).not_to have_key('ORGS_SSO_ENABLED')
    expect(env).not_to have_key('OTS_LANE_LEAK_CANARY')
    expect(env).not_to have_key('BASH_ENV')
    expect(result[:output]).not_to include(LaneHermeticProbe::CANARY)
  end

  it 'scrubs both exported-function attribute shapes' do
    # The positive half, and the reason this file is not vacuous. BASH_ENV
    # is the only way to get a `-ftx` function into the runner's own shell
    # (attributes are not preserved across exec), and if it ever stops
    # being sourced the negatives below would all pass with nothing to
    # scrub. These two lines say the runner saw both functions and cleared
    # both — the `-fx` one an `$2 == "-fx"` filter caught, and the `-ftx`
    # one it did not.
    expect(result[:scrub_trace]).to include("[lane:scrub] unset -f #{LaneHermeticProbe::PLAIN_FN}")
    expect(result[:scrub_trace]).to include("[lane:scrub] unset -f #{LaneHermeticProbe::TRACED_FN}")
  end

  it 'does not let exported shell functions reach the task process' do
    # PLAIN_FN is `-fx`; TRACED_FN is `-ftx`, which a filter matching the
    # literal string `-fx` skips. Both must be gone, from the function
    # table and from the BASH_FUNC_* entries that rebuild it.
    expect(result[:functions]).to be_empty
    expect(result[:env_lines].grep(/\ABASH_FUNC_/)).to be_empty
    # Task-process output only: the scrub trace names every function it
    # clears, so the whole capture necessarily mentions both names.
    expect(result[:task_output]).not_to include(LaneHermeticProbe::PLAIN_FN)
    expect(result[:task_output]).not_to include(LaneHermeticProbe::TRACED_FN)
  end

  it 'strips readonly exported vars and functions at the exec boundary' do
    # `unset` cannot clear these inside the runner's shell — the positive
    # trace lines prove they were there and were routed to the env -u
    # strip rather than silently surviving.
    expect(result[:scrub_trace]).to include("[lane:scrub] strip-at-exec #{LaneHermeticProbe::RO_VAR} (readonly)")
    expect(result[:scrub_trace]).to include("[lane:scrub] strip-at-exec #{LaneHermeticProbe::RO_FN} (readonly function)")
    expect(env).not_to have_key(LaneHermeticProbe::RO_VAR)
    expect(result[:task_output]).not_to include(LaneHermeticProbe::RO_FN)
  end

  it 'scrubs the function the scrub itself used to shell out to' do
    # `declare -F | awk ...` made the scrub's coverage a function of the
    # caller's environment: an exported `awk` returned nothing, which reads
    # as "no exported functions", and every other exported function — the
    # `git`/`bundle`/`docker` shadowing this block exists to stop — rode
    # through untouched. The trace lines are the positive half; the negatives
    # in the example above are what they guard.
    expect(result[:scrub_trace]).to include("[lane:scrub] unset -f #{LaneHermeticProbe::TOOL_FN}")
    expect(result[:functions]).not_to include(LaneHermeticProbe::TOOL_FN)
  end

  it 'does not let a nocasematch caller reopen the keep-list' do
    # An exported BASHOPTS is imported before line one, and `nocasematch`
    # turns the keep-list `case` into a case-insensitive filter. `ci` and
    # `Path` are distinct variables from `CI` and `PATH`; matched
    # case-insensitively they look keep-listed and are delivered verbatim.
    expect(env).not_to have_key('ci')
    expect(env).not_to have_key('Path')
    expect(env).not_to have_key('Home')
    expect(env).not_to have_key('Coverage')
    # And the real keep-list still works.
    expect(env['CI']).to eq(LaneHermeticProbe::KEEPSAKE)
  end

  it 'enumerates the environment through a shadow-proof env(1)' do
    # A readonly `env` function outlives the function scrub, and the
    # exec-boundary loop that finds non-identifier names is an ordinary
    # command word away from calling it instead of coreutils — which would
    # return nothing, strip nothing, and look exactly like a clean
    # environment. It prints the canary if it ever runs; the odd names below
    # are what its silence would have let through.
    expect(result[:scrub_trace])
      .to include("[lane:scrub] strip-at-exec #{LaneHermeticProbe::RO_TOOL_FN} (readonly function)")
    expect(result[:output]).not_to include(LaneHermeticProbe::CANARY)
    expect(result[:functions]).to be_empty
  end

  it 'strips environment entries whose names are not shell identifiers' do
    # `env 'FOO-BAR=x' tests/lanes/run ...` is legal: execve has no opinion
    # about names. Bash cannot enumerate or unset these, but it forwards
    # them across both execs, and ENV['FOO-BAR'] reads them in the task
    # process — so they leave at the exec boundary or not at all.
    LaneHermeticProbe::ODD_NAMES.each do |name|
      expect(result[:env_lines].grep(/\A#{Regexp.escape(name)}=/)).to be_empty
    end
  end

  it 'survives an allexport caller and keeps its option state to itself' do
    # SHELLOPTS=allexport in the caller's environment is imported by the
    # runner's own bash at startup. The runner must reset it before its
    # first assignment — otherwise its scrub working variables would leak
    # here as _lanes_* entries — and SHELLOPTS, being readonly-exported,
    # can only leave via the exec-boundary strip.
    expect(env).not_to have_key('SHELLOPTS')
    expect(env).not_to have_key('BASHOPTS')
    expect(env.keys.grep(/\A_lanes_/)).to be_empty
  end

  it 'passes the keep-listed variables through untouched' do
    expect(env['CI']).to eq(LaneHermeticProbe::KEEPSAKE)
    expect(env['COVERAGE']).to eq(LaneHermeticProbe::KEEPSAKE)
    expect(env['LANES_NO_AUTOSTART']).to eq('1')
  end

  it 'wins over the caller for every determinism pin' do
    # base.env owns the parity pins; tests/lanes/run owns the locale pins.
    # The caller set all four to something else.
    expect(env['NODE_ENV']).to eq('test')
    expect(env['TZ']).to eq('UTC')
    expect(env['LANG']).to eq('C.UTF-8')
    expect(env['LC_ALL']).to eq('C.UTF-8')
  end
end
