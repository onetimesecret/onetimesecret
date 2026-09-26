# spec/unit/lanes/argument_handling_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# The argument surface of tests/lanes/run (#4492): which flag combinations
# the runner accepts, which it refuses with exit 64, what --quiet exports,
# and how a lane-less --only and --which resolve through the ownership
# table. Every example is one process spawn against the `selftest` lane
# with --print-key, which returns right after the derivation and before any
# service, codegen or task — so nothing here needs a datastore and a parsing
# error (exit 64) fires before --print-key is honored, which is what makes
# the nonzero rows meaningful. The --only paths only have to exist;
# --print-key never opens them.
#
# RSPEC_OUTPUT_FILE is keep-listed by the runner, so a CI unit lane (which
# sets it through run-test-lane/action.yml) would hand it to every child
# here and the --quiet rows would trip the runner's --quiet/RSPEC_OUTPUT_FILE
# refusal and read as a parsing regression. Removed, not emptied: the
# refusal tests -n. The one example that WANTS the pairing sets it itself.
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
  def run(*args, env: {})
    Open3.capture2e(
      { 'RSPEC_OUTPUT_FILE' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner, *args, chdir: repo_root
    )
  end

  # One --print-key field, to the end of its line: spec_opts is the last
  # field of the run_dir line and its value carries spaces.
  def field(output, key)
    output[/(?:\A|\s)#{Regexp.escape(key)}=(.*)$/, 1]
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
      [64, %w[--print-key --only try/unit/base_view_try.rb -- --only-failures]],
      [64, %w[--print-key --only try/unit/base_view_try.rb --only spec/unit/lanes/hermetic_boundary_spec.rb]],
      [0,  %w[--console --print-key]],
      [0,  %w[--console --overlay billing --print-key]],
      [64, %w[--console --only spec/unit/lanes/hermetic_boundary_spec.rb --print-key]],
      [64, %w[--console --quiet --print-key]],
      [64, %w[--console --skip-codegen --print-key]],
      [64, %w[--console -- --only-failures]],
    ].each do |want, args|
      it "exits #{want} for: selftest #{args.join(' ')}" do
        output, status = probe.run('selftest', *args)
        expect(status.exitstatus).to eq(want), "exited #{status.exitstatus}:\n#{output}"
      end
    end
  end

  describe '--quiet' do
    # An env effect, not an exit code: SPEC_OPTS must carry the quiet
    # formatter under the flag and must be absent without it (default
    # output is CI's output).
    it 'selects the quiet formatter through SPEC_OPTS' do
      output, status = probe.run('selftest', '--quiet', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'spec_opts'))
        .to match(%r{\A--require \S*quiet_formatter --format Lanes::QuietFormatter\z})
    end

    it 'leaves SPEC_OPTS unset without the flag' do
      output, status = probe.run('selftest', '--print-key')
      expect(status).to be_success, output
      expect(probe.field(output, 'spec_opts')).to eq('none')
    end

    it 'refuses to replace the formatters RSPEC_OUTPUT_FILE depends on' do
      output, status = probe.run('selftest', '--quiet', '--print-key',
                                 env: { 'RSPEC_OUTPUT_FILE' => 'tmp/argument-handling-results.json' })
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('RSPEC_OUTPUT_FILE cannot be honored')
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
