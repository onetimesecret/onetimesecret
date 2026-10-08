# spec/unit/lanes/rspec_format_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'shellwords'
require 'stringio'
require_relative '../../../tests/lanes/support/rspec_format'

# Lanes::RSpecFormat (#4683): which formatter flags one rspec invocation of
# a lane gets, as a function of two environment names and a suffix. Nothing
# here runs a lane or rspec: the module is given a hash. What the rake tasks
# and the runner do with the flags is rspec_reporting_spec.rb.
RSpec.describe Lanes::RSpecFormat do
  let(:support_dir)     { File.realpath(File.join(Onetime::HOME, 'tests', 'lanes', 'support')) }
  let(:quiet_formatter) { File.join(support_dir, 'quiet_formatter') }
  let(:quiet_flags)     { ['--require', quiet_formatter, '--format', 'Lanes::QuietFormatter'] }
  let(:quiet)           { { 'LANES_RSPEC_CONSOLE' => 'quiet' } }
  let(:results)         { { 'RSPEC_OUTPUT_FILE' => 'tmp/rspec_unit_results.json' } }

  describe '.argv' do
    it 'is the progress formatter alone when nothing is set' do
      expect(described_class.argv({})).to eq(%w[--format progress])
    end

    it 'treats an empty value like an unset one, for both names' do
      env = { 'LANES_RSPEC_CONSOLE' => '', 'RSPEC_OUTPUT_FILE' => '' }

      expect(described_class.argv(env)).to eq(%w[--format progress])
    end

    it 'swaps the console formatter for the quiet one under LANES_RSPEC_CONSOLE=quiet' do
      expect(described_class.argv(quiet)).to eq(quiet_flags)
    end

    it 'requires the quiet formatter by an absolute path to a file that exists' do
      expect(quiet_formatter).to start_with('/')
      expect(File.file?("#{quiet_formatter}.rb")).to be(true)
    end

    it 'adds the JSON formatter beside progress when RSPEC_OUTPUT_FILE is set' do
      expect(described_class.argv(results))
        .to eq(%w[--format progress --format json --out tmp/rspec_unit_results.json])
    end

    it 'adds the JSON formatter beside the quiet one: neither request displaces the other' do
      expect(described_class.argv(quiet.merge(results)))
        .to eq(quiet_flags + %w[--format json --out tmp/rspec_unit_results.json])
    end

    it 'uses the console formatter the caller names when quiet was not asked for' do
      expect(described_class.argv({}, console: 'documentation')).to eq(%w[--format documentation])
      expect(described_class.argv(quiet, console: 'documentation')).to eq(quiet_flags)
    end

    it 'does not change the environment it is given' do
      env = quiet.merge(results).freeze

      expect { described_class.argv(env, suffix: 'root_fast') }.not_to raise_error
    end
  end

  describe 'the results file suffix' do
    it 'goes between the stem and .json' do
      expect(described_class.results_file(results, suffix: 'root_fast'))
        .to eq('tmp/rspec_unit_results_root_fast.json')
    end

    it 'leaves the path alone without one' do
      expect(described_class.results_file(results)).to eq('tmp/rspec_unit_results.json')
    end

    it 'is appended, with .json, to a path that has no .json of its own' do
      expect(described_class.results_file({ 'RSPEC_OUTPUT_FILE' => 'tmp/results' }, suffix: 'mfa'))
        .to eq('tmp/results_mfa.json')
    end

    it 'names no file when no results were asked for, with or without a suffix' do
      expect(described_class.results_file({})).to be_nil
      expect(described_class.results_file({}, suffix: 'root_fast')).to be_nil
      expect(described_class.argv(quiet, suffix: 'root_fast')).to eq(quiet_flags)
    end

    it 'reaches the --out flag under either console formatter' do
      expect(described_class.argv(results, suffix: 'apps_fast').last)
        .to eq('tmp/rspec_unit_results_apps_fast.json')
      expect(described_class.argv(quiet.merge(results), suffix: 'apps_fast').last)
        .to eq('tmp/rspec_unit_results_apps_fast.json')
    end

    it 'gives distinct invocations distinct files' do
      files = %w[root_fast apps_fast apps_config_ru].map { |suffix| described_class.results_file(results, suffix: suffix) }

      expect(files.uniq.length).to eq(3)
      expect(files).not_to include('tmp/rspec_unit_results.json')
    end

    ['', 'a/b', '../up', 'two words', "line\nbreak", 'dash-ed'].each do |suffix|
      it "refuses #{suffix.inspect}" do
        expect { described_class.results_file(results, suffix: suffix) }
          .to raise_error(Lanes::RSpecFormat::Error, /suffix/)
      end
    end
  end

  describe 'an invalid LANES_RSPEC_CONSOLE' do
    # The runner only ever exports `quiet`. Anything else is a typo in a
    # hand-set environment, and choosing a formatter for it would hide that.
    ['Quiet', 'QUIET', ' quiet', 'progress', 'documentation', 'true', '1', 'off', 'json'].each do |value|
      it "is refused, naming the variable, for #{value.inspect}" do
        env = { 'LANES_RSPEC_CONSOLE' => value }

        expect { described_class.argv(env) }
          .to raise_error(Lanes::RSpecFormat::Error, /LANES_RSPEC_CONSOLE must be 'quiet' or unset/)
        expect { described_class.options(env.merge(results), suffix: 'root_fast') }
          .to raise_error(Lanes::RSpecFormat::Error)
        expect { described_class.only_argv(env) }.to raise_error(Lanes::RSpecFormat::Error)
      end
    end

    it 'is an ArgumentError, so a rake leg reports it as that leg failing' do
      expect(Lanes::RSpecFormat::Error.ancestors).to include(ArgumentError, StandardError)
    end
  end

  describe '.options' do
    # What lib/tasks/spec.rake interpolates into a command line. The first
    # two are the strings it produced before this module existed.
    it 'is the flags as one string' do
      expect(described_class.options({})).to eq('--format progress')
      expect(described_class.options(results, suffix: 'root_fast'))
        .to eq('--format progress --format json --out tmp/rspec_unit_results_root_fast.json')
      expect(described_class.options(quiet.merge(results), suffix: 'root_fast'))
        .to eq("--require #{quiet_formatter} --format Lanes::QuietFormatter " \
               '--format json --out tmp/rspec_unit_results_root_fast.json')
    end

    it 'quotes a path a shell would split' do
      env = quiet.merge('RSPEC_OUTPUT_FILE' => 'tmp/my results/unit.json')

      expect(Shellwords.split(described_class.options(env, suffix: 'cli')))
        .to eq(quiet_flags + ['--format', 'json', '--out', 'tmp/my results/unit_cli.json'])
    end
  end

  describe '.only_argv' do
    it 'adds nothing when neither name is set, so .rspec decides' do
      expect(described_class.only_argv({})).to eq([])
    end

    it 'is the quiet formatter alone under quiet' do
      expect(described_class.only_argv(quiet)).to eq(quiet_flags)
    end

    it 'writes the results to <stem>_only.json' do
      expect(described_class.only_argv(quiet.merge(results)))
        .to eq(quiet_flags + %w[--format json --out tmp/rspec_unit_results_only.json])
    end

    # A --format on the command line replaces the one in .rspec, so adding
    # the JSON formatter alone would leave the console with nothing.
    it 'restates the console formatter of .rspec when it adds the JSON one without quiet' do
      expect(described_class.only_argv(results))
        .to eq(%w[--format documentation --format json --out tmp/rspec_unit_results_only.json])
    end

    it 'restates what .rspec really selects' do
      formats = File.readlines(File.join(Onetime::HOME, '.rspec'), chomp: true).grep(/\A--format\b/)

      expect(formats).to eq(["--format #{Lanes::RSpecFormat::DOCUMENTATION}"])
    end
  end

  describe '.task_suffix' do
    it 'is nil for the one task a rake process was asked to run' do
      expect(described_class.task_suffix('spec:integration:simple', ['spec:integration:simple'])).to be_nil
    end

    it 'names the task when an aggregate runs it' do
      expect(described_class.task_suffix('spec:integration:simple', ['spec:integration:all']))
        .to eq('integration_simple')
      expect(described_class.task_suffix('spec:integration:full:agnostic_on_pg', ['spec:all']))
        .to eq('integration_full_agnostic_on_pg')
    end

    it 'names the task when several were asked for at once' do
      asked = ['spec:integration:simple', 'spec:integration:full']

      expect(asked.map { |name| described_class.task_suffix(name, asked) })
        .to eq(%w[integration_simple integration_full])
    end

    it 'names the task when it is invoked with no rake command line at all' do
      expect(described_class.task_suffix('spec:api', [])).to eq('api')
    end

    it 'keeps the prefix of a task outside the spec namespace' do
      expect(described_class.task_suffix('vcr:billing:verify', ['spec:all'])).to eq('vcr_billing_verify')
    end

    it 'always yields a suffix the results file accepts' do
      %w[spec:integration:full:postgres spec:integration:migrations:sqlite vcr:billing:record].each do |name|
        expect(described_class.task_suffix(name, [])).to match(Lanes::RSpecFormat::SUFFIX)
      end
    end
  end

  describe 'as a command' do
    def main(args, env)
      out = StringIO.new
      err = StringIO.new
      [described_class.main(args, env: env, out: out, err: err), out.string, err.string]
    end

    it 'prints one argument per line' do
      status, out, err = main([], quiet.merge(results))

      expect(status).to eq(0)
      expect(out.lines(chomp: true)).to eq(quiet_flags + %w[--format json --out tmp/rspec_unit_results.json])
      expect(err).to eq('')
    end

    it 'prints the --only flags under --only' do
      status, out, = main(['--only'], results)

      expect(status).to eq(0)
      expect(out.lines(chomp: true))
        .to eq(%w[--format documentation --format json --out tmp/rspec_unit_results_only.json])
    end

    it 'prints nothing, not an empty line, when there is no flag to add' do
      expect(main(['--only'], {})).to eq([0, '', ''])
    end

    it 'keeps a path with a space on one line' do
      _, out, = main(['--only'], { 'RSPEC_OUTPUT_FILE' => 'tmp/my results/unit.json' })

      expect(out.lines(chomp: true).last).to eq('tmp/my results/unit_only.json')
    end

    it 'exits 64 with one line on standard error for an invalid console value' do
      status, out, err = main([], { 'LANES_RSPEC_CONSOLE' => 'loud' })

      expect(status).to eq(64)
      expect(out).to eq('')
      expect(err).to match(/\Aerror: LANES_RSPEC_CONSOLE must be 'quiet' or unset, not "loud".*\n\z/)
    end

    it 'exits 64 for a results path that cannot be passed one argument per line' do
      status, out, err = main(['--only'], { 'RSPEC_OUTPUT_FILE' => "tmp/a\nb.json" })

      expect(status).to eq(64)
      expect(out).to eq('')
      expect(err).to include('RSPEC_OUTPUT_FILE contains a line break')
    end

    it 'exits 64 for an argument it does not know' do
      status, out, err = main(['--suffix', 'x'], {})

      expect(status).to eq(64)
      expect(out).to eq('')
      expect(err).to start_with('error: usage: rspec_format.rb [--only]')
    end

    # The runner calls the file with plain `ruby`, before Bundler: it must
    # load with nothing but the standard library.
    it 'runs as a script without Bundler or any gem' do
      script = File.join(support_dir, 'rspec_format.rb')
      env    = {
        'LANES_RSPEC_CONSOLE' => 'quiet', 'RSPEC_OUTPUT_FILE' => 'tmp/results.json',
        'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil, 'RUBYLIB' => nil
      }
      out, err, status = Open3.capture3(env, RbConfig.ruby, '--disable-gems', script, '--only')

      expect(status.exitstatus).to eq(0), err
      expect(out.lines(chomp: true)).to eq(quiet_flags + %w[--format json --out tmp/results_only.json])
    end
  end
end
