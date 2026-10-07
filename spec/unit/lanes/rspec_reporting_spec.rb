# spec/unit/lanes/rspec_reporting_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'
require 'tmpdir'

# What a lane's rspec invocations report, and where (#4683): the quiet
# console formatter (tests/lanes/run --quiet) and the JSON results file
# (RSPEC_OUTPUT_FILE) are asked for independently and have to arrive
# together, one results file per invocation.
#
# Which flags a given environment produces is rspec_format_spec.rb. This file
# is about the three places that put them on a command line, each driven for
# real and none of them through a whole lane:
#
#   - lib/tasks/spec.rake. First by invoking every lane's rake tasks with the
#     command capture ownership_spec.rb uses, which yields the results file
#     of every rspec invocation without running one. Then by running
#     `rake spec:fast` itself, its three legs included, in a directory that
#     holds a handful of fixture specs where the repository has its trees:
#     the tasks, patterns, suffixes and leg collection are the real ones, and
#     only the examples are stand-ins.
#   - tests/lanes/run --only, against the `selftest` lane (no services) under
#     a throwaway overlay, as capture_logs_spec.rb does.
#   - tests/lanes/browser/tasks, the one lane that calls rspec itself.
#
# Every nested run is given a results path of its own. RSPEC_OUTPUT_FILE is
# on the runner's keep-list, so in CI this process has the unit lane's, and
# a nested rspec that inherited it would add a file to that lane's results.
module LaneReportingProbe
  Run = Struct.new(:stdout, :stderr, :status) do
    def exitstatus = status.exitstatus
    def all        = "#{stdout}#{stderr}"
  end

  # A nested run and what it left in its results directory.
  FixtureRun = Struct.new(:run, :files, :log) do
    def summary(name) = JSON.parse(files.fetch(name)).fetch('summary')
    def examples(name) = JSON.parse(files.fetch(name)).fetch('examples')
  end

  # The results path the capture below hands to the rake tasks. Nothing is
  # written there: the commands are recorded, not run.
  STEM = 'tmp/lane-reporting/results'

  # Runs in its own process, like the ownership oracle: loading the rake file
  # defines tasks and top-level constants. Prints one JSON object on the real
  # standard output; the tasks' own chatter goes to standard error.
  ORACLE = <<~'RUBY'
    require 'rake'
    require 'json'
    require 'shellwords'

    load 'lib/tasks/spec.rake'

    report  = $stdout
    $stdout = $stderr

    # `sh env, "one string"` or `sh env, 'bundle', 'exec', ...` from the task
    # bodies, and the command an RSpec::Core::RakeTask would have started.
    captured = []
    TOPLEVEL_BINDING.receiver.define_singleton_method(:sh) do |*args|
      words = args.reject { |arg| arg.is_a?(Hash) }
      captured << (words.size == 1 ? Shellwords.split(words.first) : words)
    end
    RSpec::Core::RakeTask.prepend(
      Module.new { define_method(:run_task) { |_verbose| captured << Shellwords.split(spec_command) } },
    )

    # The rspec invocations of ONE rake process asked to run +names+.
    invocations = lambda do |names|
      Rake::Task.tasks.each(&:reenable)
      Rake.application.init('rake', names.dup)
      captured.clear
      names.each { |name| Rake::Task[name].invoke }
      captured.filter_map do |words|
        next unless words.any? { |word| File.basename(word) == 'rspec' }

        pairs = words.each_cons(2).to_a
        {
          'out' => pairs.find { |flag, _| flag == '--out' }&.last,
          'formats' => pairs.select { |flag, _| flag == '--format' }.map(&:last),
          'requires' => pairs.select { |flag, _| flag == '--require' }.map(&:last),
        }
      end
    end

    # A lane's tasks file starts one rake process per task.
    lanes = Dir.glob('tests/lanes/*/tasks').sort.to_h do |tasks|
      names = File.read(tasks).scan(/^\s*bundle exec rake ([a-z_:]+)/).flatten
      [tasks.split('/')[-2], names.flat_map { |name| invocations.call([name]) }]
    end
    together = [
      %w[spec:integration:all],
      %w[spec:integration:all:with_postgres],
      %w[spec:all],
      %w[smoke:rspec],
      %w[spec:integration:simple spec:integration:full spec:api],
    ].to_h { |names| [names.join(' '), invocations.call(names)] }

    report.puts JSON.generate('lanes' => lanes, 'together' => together)
  RUBY

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

  def quiet_formatter
    File.join(File.realpath(File.join(repo_root, 'tests', 'lanes', 'support')), 'quiet_formatter')
  end

  # Every rspec invocation the rake tasks would make under --quiet with a
  # results file, as {'lanes' => {lane => [...]}, 'together' => {...}}. One
  # subprocess for the whole file.
  def invocations
    return @invocations if defined?(@invocations)

    env              = { 'RSPEC_OUTPUT_FILE' => "#{STEM}.json", 'LANES_RSPEC_CONSOLE' => 'quiet' }
    out, err, status = Open3.capture3(env, 'bundle', 'exec', 'ruby', '-e', ORACLE, chdir: repo_root)
    raise "reporting oracle failed (#{status.exitstatus}):\n#{err}\n#{out}" unless status.success?

    @invocations = JSON.parse(out)
  end

  # A directory laid out like the repository as far as spec:fast's three
  # patterns are concerned, with one small spec file per leg. A red tree
  # adds a failing example to the first leg and makes the third leg's
  # process die inside an example, before rspec writes its results.
  def write_tree(dir, red:)
    write(dir, 'spec/unit/reporting_fixture_spec.rb', <<~RUBY)
      RSpec.describe 'reporting fixture root leg' do
        it('root passes one') { expect(1).to eq(1) }
        it('root passes two') { expect(2).to eq(2) }
        it('root is pending') { skip 'the pending example of the fixture' }
        #{"it('root fails on purpose') { expect(1).to eq(2) }" if red}
      end
    RUBY
    write(dir, 'apps/api/fixture/spec/reporting_fixture_spec.rb', <<~RUBY)
      RSpec.describe 'reporting fixture apps leg' do
        it('apps passes one') { expect(1).to eq(1) }
        it('apps passes two') { expect(2).to eq(2) }
        it('apps passes three') { expect(3).to eq(3) }
      end
    RUBY
    write(dir, 'apps/web/core/spec/controllers/config_generator_spec.rb', <<~RUBY)
      RSpec.describe 'reporting fixture config.ru leg' do
        it('config.ru passes one') { #{red ? 'exit!(7)' : 'expect(1).to eq(1)'} }
      end
    RUBY
  end

  def write(dir, relative, contents)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  # `bundle exec rake spec:fast`, as the unit lane's tasks file runs it, with
  # the fixture tree as the working directory. The directory has no .rspec,
  # so no spec_helper and no application code is loaded. SPEC_OPTS asks for
  # random order, which the application's spec_helper otherwise configures,
  # so that there is a seed to report; it carries no formatter.
  def rake_fast(tree, results, env = {})
    stdout, stderr, status = Open3.capture3(
      {
        'RSPEC_OUTPUT_FILE' => results,
        'SPEC_OPTS' => '--order random',
        'BUNDLE_GEMFILE' => File.join(repo_root, 'Gemfile'),
        'LANES_RSPEC_STATUS_FILE' => nil, 'COVERAGE' => nil, 'SPEC' => nil
      }.merge(env),
      'bundle', 'exec', 'rake', '-f', File.join(repo_root, 'Rakefile'), 'spec:fast',
      chdir: tree
    )
    Run.new(stdout, stderr, status)
  end

  # One `rake spec:fast` per scenario for the whole file: the run, and the
  # results directory as {file name => contents}, read before the directory
  # goes away.
  FAST_SCENARIOS = {
    green_quiet: { red: false, console: 'quiet' },
    green_progress: { red: false, console: nil },
    red_quiet: { red: true, console: 'quiet' },
    invalid_console: { red: false, console: 'loud' },
  }.freeze

  def fast(scenario)
    (@fast ||= {})[scenario] ||= Dir.mktmpdir('ots-lane-reporting') do |dir|
      settings = FAST_SCENARIOS.fetch(scenario)
      tree     = File.join(dir, 'tree')
      results  = File.join(dir, 'results')
      FileUtils.mkdir_p([tree, results])
      write_tree(tree, red: settings.fetch(:red))

      nested = rake_fast(tree, File.join(results, 'unit.json'), 'LANES_RSPEC_CONSOLE' => settings.fetch(:console))
      FixtureRun.new(nested, read_directory(results), nil)
    end
  end

  # One real rspec process started by `tests/lanes/run --quiet --only`, on a
  # fixture file with two passing, one pending and one failing example.
  # `--options` keeps .rspec, and with it spec_helper and the application,
  # out of the nested process, and asks for the random order the
  # application's spec_helper configures.
  def only_failure
    @only_failure ||= Dir.mktmpdir('ots-lane-reporting') do |dir|
      results = File.join(dir, 'results')
      FileUtils.mkdir_p(results)
      fixture = write(dir, 'reporting_fixture_spec.rb', <<~RUBY)
        RSpec.describe 'reporting fixture for --only' do
          it('only passes one') { expect(1).to eq(1) }
          it('only passes two') { expect(2).to eq(2) }
          it('only is pending') { skip 'the pending example of the fixture' }
          it('only fails on purpose') { expect(1).to eq(2) }
        end
      RUBY
      options = write(dir, 'rspec-options', "--order random\n")

      with_scratch do |overlay, log|
        nested = run('selftest', '--overlay', overlay, '--quiet', '--only', fixture, '--', '--options', options,
                     env: { 'RSPEC_OUTPUT_FILE' => File.join(results, 'only.json') })
        FixtureRun.new(nested, read_directory(results), File.read(log))
      end
    end
  end

  def read_directory(dir)
    Dir.children(dir).sort.to_h { |name| [name, File.read(File.join(dir, name))] }
  end

  # stdout and stderr apart. CI is removed so the lane keeps its derived
  # datastore index; the results path is the caller's to give.
  def run(*args, env: {})
    stdout, stderr, status = Open3.capture3(
      { 'CI' => nil, 'RSPEC_OUTPUT_FILE' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner, *args, chdir: repo_root
    )
    Run.new(stdout, stderr, status)
  end

  # A private run directory under tmp/lanes/selftest/, as in
  # capture_logs_spec.rb, so no example shares last.log with another run.
  def with_scratch
    overlay      = "rspec-reporting-#{Process.pid}-#{SecureRandom.hex(4)}"
    overlay_path = File.join(repo_root, 'tests', 'lanes', 'overlays', "#{overlay}.env")
    directory    = File.join(repo_root, 'tmp', 'lanes', 'selftest', overlay)
    File.write(overlay_path, '')
    yield overlay, File.join(directory, 'last.log')
  ensure
    FileUtils.rm_f(overlay_path) if overlay_path
    FileUtils.rm_rf(directory) if directory
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
end

RSpec.describe 'lane rspec reporting' do
  let(:probe)       { LaneReportingProbe }
  let(:stem)        { LaneReportingProbe::STEM }
  let(:quiet_flags) { "--require #{probe.quiet_formatter} --format Lanes::QuietFormatter" }

  # A line of the progress formatter: one mark per example and nothing else.
  let(:progress_line) { /^[.F*]+$/ }

  describe 'the results file of each rake invocation, under --quiet' do
    let(:lanes)    { probe.invocations.fetch('lanes') }
    let(:together) { probe.invocations.fetch('together') }

    def outs(invocations)
      invocations.map { |invocation| invocation.fetch('out') }
    end

    it 'gives the unit lane one file per spec:fast leg' do
      expect(outs(lanes.fetch('unit')))
        .to eq(%w[root_fast apps_fast apps_config_ru].map { |leg| "#{stem}_#{leg}.json" })
    end

    # The names .github/actions/run-test-lane collects by tmp/<stem>*.json,
    # and migration-tests.yml by the bare path. A lane that is not listed
    # here fails the example below until its file name is decided.
    {
      'api' => [''],
      'billing' => [''],
      'billing-integration' => [''],
      'disabled' => [''],
      'full-mfa' => ['_mfa'],
      'full-pg' => [''],
      'full-pg-agnostic' => [''],
      'full-saml-platform' => ['_saml_platform'],
      'full-sqlite' => [''],
      'migrations-pg' => [''],
      'migrations-sqlite' => [''],
      'simple' => [''],
      'unit' => %w[_root_fast _apps_fast _apps_config_ru],
    }.each do |lane, suffixes|
      it "keeps the file name(s) CI collects for the #{lane} lane" do
        expect(outs(lanes.fetch(lane))).to eq(suffixes.map { |suffix| "#{stem}#{suffix}.json" })
      end
    end

    it 'covers every lane that runs rspec through rake' do
      through_rake = lanes.reject { |_, invocations| invocations.empty? }.keys.sort

      expect(through_rake).to eq(%w[api billing billing-integration disabled full-mfa full-pg full-pg-agnostic
                                    full-saml-platform full-sqlite migrations-pg migrations-sqlite simple unit])
    end

    it 'never gives two invocations of one lane the same file' do
      lanes.each do |lane, invocations|
        expect(outs(invocations).uniq).to eq(outs(invocations)), "lane '#{lane}' writes #{outs(invocations)}"
      end
    end

    # The same tasks, run by one rake process beside others. Left with the
    # bare name each would truncate the file the one before it wrote, and
    # the run would report only its last invocation.
    it 'suffixes the tasks an aggregate runs together, by their own names' do
      expect(outs(together.fetch('spec:integration:all')))
        .to eq(%w[integration_simple integration_full integration_disabled mfa saml_platform]
                 .map { |suffix| "#{stem}_#{suffix}.json" })
    end

    it 'never gives two invocations of one rake process the same file' do
      together.each do |names, invocations|
        expect(invocations.length).to be > 1, "rake #{names} made #{invocations.length} rspec invocation(s)"
        expect(outs(invocations).uniq).to eq(outs(invocations)), "rake #{names} writes #{outs(invocations)}"
        expect(outs(invocations)).not_to include("#{stem}.json"), "rake #{names} writes the bare results file"
      end
    end

    it 'gives every invocation the quiet console formatter and the JSON formatter, in that order' do
      all = lanes.values.flatten + together.values.flatten

      expect(all).not_to be_empty
      all.each do |invocation|
        expect(invocation.fetch('formats')).to eq(%w[Lanes::QuietFormatter json]), invocation.inspect
        expect(invocation.fetch('requires')).to eq([probe.quiet_formatter]), invocation.inspect
        expect(invocation.fetch('out')).to match(/\A#{Regexp.escape(stem)}(?:_[a-z0-9_]+)?\.json\z/)
      end
    end
  end

  describe 'rake spec:fast on a fixture tree, with --quiet and a results file' do
    let(:legs)  { %w[root_fast apps_fast apps_config_ru] }
    let(:green) { probe.fast(:green_quiet) }

    def leg_file(leg)
      "unit_#{leg}.json"
    end

    it 'leaves one parseable results file per leg, and their example counts add up' do
      expect(green.run.exitstatus).to eq(0), green.run.all
      expect(green.files.keys).to eq(legs.map { |leg| leg_file(leg) }.sort)

      summaries = legs.to_h { |leg| [leg, green.summary(leg_file(leg))] }
      expect(summaries.transform_values { |summary| summary.fetch('example_count') })
        .to eq('root_fast' => 3, 'apps_fast' => 3, 'apps_config_ru' => 1)
      expect(summaries.values.sum { |summary| summary.fetch('example_count') }).to eq(7)
      expect(summaries.values.sum { |summary| summary.fetch('failure_count') }).to eq(0)
      expect(summaries.values.sum { |summary| summary.fetch('pending_count') }).to eq(1)
    end

    it 'prints the pending example, each summary and each seed, and nothing per passing example' do
      stdout = green.run.stdout

      expect(stdout).to include('Pending:')
      expect(stdout).to include('the pending example of the fixture')
      expect(stdout.scan(/^\d+ examples?, 0 failures(?:, 1 pending)?$/))
        .to contain_exactly('3 examples, 0 failures, 1 pending', '3 examples, 0 failures', '1 example, 0 failures')
      # rspec announces the seed when a run starts and again when it ends.
      expect(stdout.scan(/^Randomized with seed \d+$/).length).to be >= 3
      expect(stdout).not_to match(progress_line)
      expect(stdout).not_to match(/passes (?:one|two|three)/)
      expect(stdout).to include('spec:fast leg summary (3/3 ok):')
    end

    # The control for the example above: the same run without the request is
    # the progress formatter, and writes the same results.
    it 'prints a mark per example without --quiet, and writes the same results' do
      progress = probe.fast(:green_progress)

      expect(progress.run.exitstatus).to eq(0), progress.run.all
      expect(progress.run.stdout.scan(progress_line).sum(&:length)).to eq(7)
      expect(legs.sum { |leg| progress.summary(leg_file(leg)).fetch('example_count') }).to eq(7)
      expect(legs.map { |leg| progress.summary(leg_file(leg)).except('duration') })
        .to eq(legs.map { |leg| green.summary(leg_file(leg)).except('duration') })
    end

    context 'when one leg has a failure and another dies before writing its results' do
      let(:red) { probe.fast(:red_quiet) }

      it 'fails the task, having run every leg' do
        expect(red.run.exitstatus).to eq(1), red.run.all
        expect(red.run.stdout).to include('spec:fast leg summary (1/3 ok):')
        expect(red.run.stdout).to match(/^\s+spec:root_fast\s+FAILED \(exit 1\)$/)
        expect(red.run.stdout).to match(/^\s+spec:apps_fast\s+ok$/)
        expect(red.run.stdout).to match(/^\s+spec:apps_config_ru\s+FAILED \(exit 7\)$/)
        expect(red.run.stderr).to include('spec:fast: 2 of 3 legs failed: spec:root_fast, spec:apps_config_ru')
      end

      it 'prints the failure with its location, the pending example, the summary and the seed' do
        stdout = red.run.stdout

        expect(stdout).to include('Failures:')
        expect(stdout).to include('reporting fixture root leg root fails on purpose')
        expect(stdout).to match(%r{^\s+# \./spec/unit/reporting_fixture_spec\.rb:5:in})
        expect(stdout).to match(%r{^rspec \./spec/unit/reporting_fixture_spec\.rb:5 # })
        expect(stdout).to include('the pending example of the fixture')
        expect(stdout).to match(/^4 examples, 1 failure, 1 pending$/)
        expect(stdout).to match(/^Randomized with seed \d+$/)
        expect(stdout).not_to match(progress_line)
        expect(stdout).not_to match(/passes (?:one|two|three)/)
      end

      it "records the failure in the failing leg's results file" do
        expect(red.summary(leg_file('root_fast')))
          .to include('example_count' => 4, 'failure_count' => 1, 'pending_count' => 1)
        failed = red.examples(leg_file('root_fast')).select { |example| example['status'] == 'failed' }
        expect(failed.map { |example| example['line_number'] }).to eq([5])
      end

      # rspec opens --out when it starts and writes the document when it
      # finishes, so a leg whose process dies in between leaves a file with
      # nothing in it. Its examples are in no results file; the exit status
      # of the run is what says so. The other legs' files are not touched.
      it "leaves the dead leg's results file empty and the other legs' files whole" do
        expect(red.files.keys).to eq(legs.map { |leg| leg_file(leg) }.sort)
        expect(red.files.fetch(leg_file('apps_config_ru'))).to eq('')
        expect(red.summary(leg_file('apps_fast'))).to include('example_count' => 3, 'failure_count' => 0)
        expect(red.summary(leg_file('root_fast'))).to include('example_count' => 4)
      end
    end

    it 'fails every leg, naming the variable, for an invalid LANES_RSPEC_CONSOLE' do
      invalid = probe.fast(:invalid_console)

      expect(invalid.run.exitstatus).to eq(1), invalid.run.all
      expect(invalid.run.stdout.scan(/FAILED \(LANES_RSPEC_CONSOLE must be 'quiet' or unset, not "loud"/).length)
        .to eq(3)
      expect(invalid.files).to be_empty
    end
  end

  describe 'tests/lanes/run --only' do
    before do
      major = probe.path_bash_major
      floor = probe.bash_floor
      skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
    end

    # Never written: the examples that use it start a stub, not rspec.
    let(:results)      { File.join(Dir.tmpdir, 'ots-lane-reporting-unwritten', 'only.json') }
    let(:only_results) { results.sub(/\.json\z/, '_only.json') }
    let(:target)       { 'spec/unit/lanes/rspec_reporting_spec.rb' }

    # The stub stands in for `bundle exec ...` and prints the arguments it
    # was started with.
    def stubbed(*args, env: {})
      probe.with_scratch do |overlay, _log|
        probe.with_fake_commands('bundle' => 'echo "fake-bundle:$*"') do |fake_path|
          probe.run('selftest', '--overlay', overlay, *args, env: env.merge('PATH' => fake_path))
        end
      end
    end

    it 'adds no formatter when neither --quiet nor a results file was asked for' do
      run = stubbed('--only', target)

      expect(run.exitstatus).to eq(0), run.all
      expect(run.stdout).to include("fake-bundle:exec rspec #{target}\n")
    end

    it 'adds the quiet formatter alone under --quiet' do
      run = stubbed('--quiet', '--only', target)

      expect(run.exitstatus).to eq(0), run.all
      expect(run.stdout).to include("fake-bundle:exec rspec #{target} #{quiet_flags}\n")
    end

    it 'adds the JSON formatter, writing <stem>_only.json, and restates the console formatter of .rspec' do
      run = stubbed('--only', target, env: { 'RSPEC_OUTPUT_FILE' => results })

      expect(run.exitstatus).to eq(0), run.all
      expect(run.stdout)
        .to include("fake-bundle:exec rspec #{target} --format documentation --format json --out #{only_results}\n")
    end

    it 'adds both under --quiet with a results file, ahead of the arguments after --' do
      run = stubbed('--quiet', '--only', target, '--', '--only-failures', env: { 'RSPEC_OUTPUT_FILE' => results })

      expect(run.exitstatus).to eq(0), run.all
      expect(run.stdout)
        .to include("fake-bundle:exec rspec #{target} #{quiet_flags} --format json --out #{only_results} --only-failures\n")
    end

    # Tryouts has its own flags and no results file: --agent prints the
    # failures and the summary, with or without --quiet.
    it 'gives a tryouts file the same command with and without --quiet' do
      tryout = 'try/unit/base_view_try.rb'
      plain  = stubbed('--only', tryout, env: { 'RSPEC_OUTPUT_FILE' => results })
      quiet  = stubbed('--quiet', '--only', tryout, env: { 'RSPEC_OUTPUT_FILE' => results })

      [plain, quiet].each do |run|
        expect(run.exitstatus).to eq(0), run.all
        expect(run.stdout).to include("fake-bundle:exec try --agent #{tryout}\n")
        expect(run.stdout).not_to include('--format')
      end
    end

    it 'stops before the command, with the reason in last.log, when the flags cannot be chosen' do
      probe.with_scratch do |overlay, log|
        probe.with_fake_commands('bundle' => 'echo "fake-bundle:$*"') do |fake_path|
          run = probe.run('selftest', '--overlay', overlay, '--only', target,
                          env: { 'PATH' => fake_path, 'RSPEC_OUTPUT_FILE' => "tmp/line\nbreak.json" })

          expect(run.exitstatus).to eq(64), run.all
          expect(run.stderr).to include('RSPEC_OUTPUT_FILE contains a line break')
          expect(run.stderr).to include('could not choose the rspec formatters for --only')
          expect(run.stdout).not_to include('fake-bundle:')
          expect(File.read(log)).to include('could not choose the rspec formatters for --only')
          expect(File.read(log).lines.grep(/^\[lane:selftest\] log: .* \(exit 64\)$/).length).to eq(1)
        end
      end
    end

    # The real thing: rspec, started by the runner (LaneReportingProbe.only_failure).
    describe 'a failing spec file under --quiet with a results file' do
      let(:failure) { probe.only_failure }
      let(:stdout)  { failure.run.stdout }

      it "keeps rspec's exit status" do
        expect(failure.run.exitstatus).to eq(1), failure.run.all
        expect(failure.log.lines.last).to match(/^\[lane:selftest\] log: .* \(exit 1\)$/)
      end

      it 'prints the failure with its location, the pending example, the summary and the seed' do
        expect(stdout).to include('Failures:')
        expect(stdout).to include('reporting fixture for --only only fails on purpose')
        expect(stdout).to match(/^\s+# \S*reporting_fixture_spec\.rb:5:in/)
        expect(stdout).to match(/^rspec \S*reporting_fixture_spec\.rb:5 # /)
        expect(stdout).to include('Pending:')
        expect(stdout).to include('the pending example of the fixture')
        expect(stdout).to match(/^4 examples, 1 failure, 1 pending$/)
        expect(stdout).to match(/^Randomized with seed \d+$/)
      end

      it 'prints nothing per passing example' do
        expect(stdout).not_to match(/only passes (?:one|two)/)
        expect(stdout).not_to match(progress_line)
      end

      it 'writes the results to <stem>_only.json and to no other file' do
        expect(failure.files.keys).to eq(['only_only.json'])
        expect(failure.summary('only_only.json'))
          .to include('example_count' => 4, 'failure_count' => 1, 'pending_count' => 1)
      end
    end
  end

  describe 'tests/lanes/browser/tasks' do
    # The engine preflight is satisfied by a `node` that reports nothing
    # missing; `bundle` prints the rspec command it was given.
    def browser_tasks(env)
      commands = { 'node' => 'echo ""', 'bundle' => 'echo "fake-bundle:$*"' }
      probe.with_fake_commands(commands) do |fake_path|
        Open3.capture2e(
          { 'RSPEC_OUTPUT_FILE' => nil, 'LANES_RSPEC_CONSOLE' => nil }.merge(env).merge('PATH' => fake_path),
          'bash', '-euo', 'pipefail', File.join(probe.repo_root, 'tests', 'lanes', 'browser', 'tasks'),
          chdir: probe.repo_root
        )
      end
    end

    before do
      major = probe.path_bash_major
      floor = probe.bash_floor
      skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
    end

    it 'prints progress by default' do
      output, status = browser_tasks({})

      expect(status).to be_success, output
      expect(output).to eq("fake-bundle:exec rspec tests/browser --format progress\n")
    end

    it 'writes the results file CI names, without a suffix' do
      output, status = browser_tasks('RSPEC_OUTPUT_FILE' => 'tmp/rspec_browser_results.json')

      expect(status).to be_success, output
      expect(output)
        .to eq("fake-bundle:exec rspec tests/browser --format progress --format json --out tmp/rspec_browser_results.json\n")
    end

    it 'takes the quiet formatter under --quiet and still writes the results file' do
      output, status = browser_tasks('LANES_RSPEC_CONSOLE' => 'quiet',
                                     'RSPEC_OUTPUT_FILE' => 'tmp/rspec_browser_results.json')

      expect(status).to be_success, output
      expect(output)
        .to eq("fake-bundle:exec rspec tests/browser #{quiet_flags} --format json --out tmp/rspec_browser_results.json\n")
    end

    it 'runs nothing for an invalid LANES_RSPEC_CONSOLE' do
      output, status = browser_tasks('LANES_RSPEC_CONSOLE' => 'loud')

      expect(status.exitstatus).to eq(64), output
      expect(output).to include('LANES_RSPEC_CONSOLE must be')
      expect(output).not_to include('fake-bundle:')
    end
  end
end
