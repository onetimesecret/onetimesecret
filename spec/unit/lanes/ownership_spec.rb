# spec/unit/lanes/ownership_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'

# tests/lanes/ownership — the path -> lane table behind `tests/lanes/run
# --which`, lane inference for a lane-less `--only` and `run-all --changed`
# — is a hand transcription of the paths the lanes' rake tasks pass to
# rspec and tryouts (lib/tasks/spec.rake). The runner lane checks it
# against the tasks files and the directories on disk, but both of those
# are lists too: nothing there proves the transcription matches what the
# tasks SELECT, so a task that gained a subtree or an exclude pattern left
# the table answering wrong with every check green. This spec closes that
# gap, and needs Ruby to do it, which is why it lives in the unit lane.
#
# Method: read each lane's tasks file for the rake tasks it runs (the same
# regex the runner lane uses), invoke every one of them in a subprocess with
# `sh` captured — nothing runs; the captured argv is the task's whole
# effect — and model each captured rspec command's file selection through
# rspec's own Configuration, so `--exclude-pattern` resolves exactly as it
# does in the task's process. spec:fast is the exception: its legs are
# RSpec::Core::RakeTask objects whose patterns SpecSelection.lane_claims
# already models from the same constants. Then ask `tests/lanes/run --which`
# for a sample of every (tree, owner set) pair and every unowned tree, and
# require the answers to agree.
#
# Load-level on purpose, matching the table's definition: a lane owns a
# file when its task loads it. `--tag` filters are example metadata (a whole
# file may carry the tag at its top describe, or one example in twenty may)
# and are not a question a path resolver answers; the table names every
# loading lane and the README says the tag then decides what runs.
module LaneOwnershipProbe
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

  # Runs in its own process: loading the rake files defines tasks and
  # top-level constants (APP_SPECS, ROOT_FAST_PATTERN, ...) that have no
  # business in the spec process that runs everything after this file.
  # Prints one JSON object, lane => [repo-relative files its tasks select].
  ORACLE = <<~'RUBY'
    require 'rake'
    require 'rspec/core'
    require 'json'
    require 'shellwords'

    load 'lib/tasks/spec.rake'
    load 'lib/tasks/spec_selection.rake'

    # The task bodies call `sh` on main (they were loaded at top level), so a
    # singleton method there shadows the FileUtils one rake mixed in.
    captured = []
    TOPLEVEL_BINDING.receiver.define_singleton_method(:sh) { |*args| captured << args }

    files_for_rspec = lambda do |paths, exclude|
      cfg = RSpec::Core::Configuration.new
      cfg.exclude_pattern = exclude if exclude
      cfg.files_or_directories_to_run = paths
      cfg.files_to_run.map { |f| f.delete_prefix("#{Dir.pwd}/") }.sort.uniq
    end

    # `sh env, "one string"` or `sh env, 'bundle', 'exec', ...`; only rspec and
    # tryouts commands select test files (verify_dual_url runs a ruby -e).
    parse = lambda do |args|
      words = args.reject { |a| a.is_a?(Hash) }
      words = Shellwords.split(words.first) if words.size == 1
      next nil unless words[0..1] == %w[bundle exec] && %w[rspec tryouts].include?(words[2])

      runner = words[2]
      paths = []
      exclude = nil
      rest = words[3..]
      while (word = rest.shift)
        case word
        when '--exclude-pattern' then exclude = rest.shift
        when '--tag', '--format', '--out' then rest.shift
        when /\A-/ then next
        else paths << word
        end
      end
      if runner == 'rspec'
        files_for_rspec.call(paths, exclude)
      else
        paths.flat_map { |p| File.directory?(p) ? Dir.glob("#{p}/**/*_try.rb") : [p] }.sort.uniq
      end
    end

    lanes = {}
    Dir.glob('tests/lanes/*/tasks').sort.each do |tasks|
      lane = tasks.split('/')[-2]
      task_names = File.read(tasks).scan(/^\s*bundle exec rake ([a-z_:]+)/).flatten
      next if task_names.empty?

      lanes[lane] = task_names.flat_map do |name|
        if name == 'spec:fast'
          SpecSelection.lane_claims.fetch('spec:fast')
        else
          captured.clear
          Rake::Task[name].invoke
          captured.filter_map { |args| parse.call(args) }.flatten
        end
      end.sort.uniq
    end
    puts JSON.generate(lanes)
  RUBY

  # lane => files, from the rake tasks. One subprocess for the whole file.
  def selection
    return @selection if defined?(@selection)

    out, err, status = Open3.capture3('bundle', 'exec', 'ruby', '-e', ORACLE, chdir: repo_root)
    raise "ownership oracle failed (#{status.exitstatus}):\n#{err}\n#{out}" unless status.success?

    @selection = JSON.parse(out)
  end

  # file => sorted owning lanes, for every file some task selects.
  def owners
    @owners ||= selection.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(lane, files), acc|
      files.each { |f| acc[f] << lane }
    end.transform_values(&:sort)
  end

  # Every test file on disk the table could be asked about.
  def on_disk
    @on_disk ||= Dir.chdir(repo_root) do
      (Dir.glob('{spec,apps/*/*/spec}/**/*_spec.rb') + Dir.glob('{try,apps/*/*/try}/**/*_try.rb')).sort
    end
  end

  # The tree a file sits in, at the depth the rake tasks dispatch on:
  # spec/<tree> and try/<tree>, one level deeper under integration/ (the
  # auth mode), apps/<type>/<name>/spec or /try, again one deeper under
  # integration/. A file directly in one of those directories is its own
  # tree (try/integration names three such files).
  def tree(file)
    segments = file.split('/')
    app = segments.first == 'apps'
    depth = app ? 4 : 2
    depth += (app ? 2 : 1) if segments[depth - 1] == 'integration'
    segments.first(depth).join('/')
  end

  # What distinguishes two files for the table is the tree and the owner
  # set, so one file per (tree, owner set) pair covers every row — and a
  # subtree with a different owner set (migrations/ under a full tree) is
  # its own sample — without asking `--which` for all ~1,500 files. A
  # file's owner set is [] when no task selects it.
  def sample
    @sample ||= on_disk.group_by { |f| [tree(f), owners.fetch(f, [])] }.values.map(&:first)
  end

  def which(file)
    out, err, status = Open3.capture3(runner, '--which', file, chdir: repo_root)
    [status.exitstatus, out.split("\n").sort, err]
  end

  # The table's own functions, run by the shell that defines them: one bash
  # process sourcing tests/lanes/ownership, then the given script, with the
  # paths as positional arguments. The runner scrubs its environment before
  # sourcing the file; here nothing depends on the environment, so a plain
  # non-login shell is the same reader.
  def ownership_shell(script, *paths)
    out, err, status = Open3.capture3(
      'bash', '--noprofile', '--norc', '-c', "source tests/lanes/ownership\n#{script}", 'bash', *paths,
      chdir: repo_root
    )
    raise "tests/lanes/ownership shell failed (#{status.exitstatus}):\n#{err}\n#{out}" unless status.success?

    out
  end

  # lane => rake tasks, as tests/lanes/ownership records them.
  def owner_tasks
    @owner_tasks ||= ownership_shell(<<~'BASH').lines.to_h { |l| k, v = l.chomp.split("\t", 2); [k, v.to_s.split.sort.uniq] }
      for lane in "${!LANES_OWNER_TASKS[@]}"; do printf '%s\t%s\n' "${lane}" "${LANES_OWNER_TASKS[${lane}]}"; done
    BASH
  end

  # lane => rake tasks, as each lane's tasks file actually runs them — the
  # same regex the oracle above reads the tasks files with.
  def tasks_run
    @tasks_run ||= Dir.chdir(repo_root) do
      Dir.glob('tests/lanes/*/tasks').sort.to_h do |tasks|
        [tasks.split('/')[-2], File.read(tasks).scan(/^\s*bundle exec rake ([a-z_:]+)/).flatten.sort.uniq]
      end
    end
  end

  def lanes_all
    @lanes_all ||= ownership_shell('lanes_all').split("\n")
  end

  # path => owning lanes for many paths in one shell, in the order given.
  def lanes_for_paths(paths)
    out = ownership_shell(<<~'BASH', *paths)
      for p in "$@"; do printf '%s\t' "${p}"; lanes_for_path "${p}" | tr '\n' ','; printf '\n'; done
    BASH
    out.lines.to_h { |l| k, v = l.chomp.split("\t", 2); [k, v.to_s.split(',')] }
  end
end

RSpec.describe 'tests/lanes/ownership against lib/tasks/spec.rake' do
  let(:probe) { LaneOwnershipProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'derives a non-empty selection for every rake lane' do
    # The oracle is only worth trusting if it saw something: a lane whose
    # tasks all parsed to nothing would make every `--which` below pass
    # against an empty expectation.
    rake_lanes = probe.selection
    expect(rake_lanes.keys).to include('unit', 'simple', 'full-sqlite', 'full-pg', 'api')
    empty = rake_lanes.select { |_, files| files.empty? }.keys
    expect(empty).to be_empty, "no files derived for lane(s) #{empty.join(', ')}"
  end

  it 'answers --which with exactly the lanes whose tasks select the file' do
    mismatches = probe.sample.filter_map do |file|
      want = probe.owners.fetch(file, [])
      status, got, err = probe.which(file)
      if want.empty?
        next if status == 64 && got.empty?

        "#{file}: no task selects it; --which exited #{status} with #{got.inspect} #{err.strip}"
      else
        next if status.zero? && got == want

        "#{file}: tasks select it in #{want.inspect}; --which exited #{status} with #{got.inspect} #{err.strip}"
      end
    end

    expect(mismatches).to be_empty, <<~MSG
      tests/lanes/ownership disagrees with lib/tasks/spec.rake for #{mismatches.size} sampled file(s):
      #{mismatches.map { |m| "  #{m}" }.join("\n")}

      Fix the table (tests/lanes/ownership), or — if a task's paths changed on
      purpose — the row the directory walk below keeps for that directory too.
    MSG
  end
end

# The other direction. The rake oracle above proves the table agrees with
# what the tasks SELECT; these prove the table and the tree on disk agree
# about what EXISTS — including the trees no task selects, which the oracle
# never sees. Both run the real bash implementation (lanes_for_path,
# lanes_all, LANES_OWNER_TASKS) through a shell that sources the file; only
# the expectations are organized here.
RSpec.describe 'tests/lanes/ownership against the lane directories' do
  let(:probe) { LaneOwnershipProbe }

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  it 'records, per lane, exactly the rake tasks its tasks file runs' do
    # A lane that picks up a task (or drops one) changes what paths it
    # owns, and that has to be a table edit in the same change.
    expect(probe.owner_tasks.keys.sort).to eq(probe.tasks_run.keys.sort)
    probe.tasks_run.each do |lane, tasks|
      expect(probe.owner_tasks[lane]).to eq(tasks),
                                         "lane '#{lane}' runs rake tasks #{tasks} but tests/lanes/ownership records #{probe.owner_tasks[lane]}"
    end
  end

  it 'fans a shared path out to every lane directory except smoke' do
    on_disk = Dir.chdir(probe.repo_root) do
      Dir.glob('tests/lanes/*/').map { |d| d.split('/').last }.select do |lane|
        File.file?("tests/lanes/#{lane}/tasks") && File.file?("tests/lanes/#{lane}/env")
      end
    end
    expect(probe.lanes_all).to eq((on_disk - ['smoke']).sort)
  end

  # `<lanes> <pattern>`: bash-style globs (`*` spans `/`), first match
  # wins, `shared` means every lane (lanes_all), `none` means no lane runs
  # it — the tolerated ones are listed by name so a new one cannot hide
  # among them.
  EXPECTED = [
    %w[api                                          spec/api],
    %w[browser                                      tests/browser],
    %w[browser                                      tests/browser/*],
    %w[unit                                         spec/cli],
    %w[unit                                         spec/lib],
    %w[unit                                         spec/unit],
    %w[shared                                       spec/support],
    %w[simple,disabled,full-sqlite,full-pg-agnostic spec/integration/all],
    %w[disabled                                     spec/integration/disabled],
    %w[full-sqlite,full-pg,full-pg-agnostic         spec/integration/full],
    %w[simple                                       spec/integration/simple],
    %w[full-sqlite,full-pg,migrations-sqlite        spec/integration/full/database_triggers/sqlite_spec.rb],
    %w[full-sqlite,full-pg,migrations-pg            spec/integration/full/database_triggers/postgres_spec.rb],
    %w[full-sqlite,full-pg,migrations-pg            spec/integration/full/postgres_infrastructure_spec.rb],
    %w[unit                                         apps/*/*/spec],
    %w[full-sqlite,full-pg                          apps/*/*/spec/integration/full/migrations/*_spec.rb],
    %w[full-sqlite,full-pg,full-pg-agnostic         apps/*/*/spec/integration/full],
    %w[full-mfa                                     apps/*/*/spec/integration/full_mfa],
    %w[full-saml-platform                           apps/*/*/spec/integration/full_saml_platform],
    %w[simple                                       apps/*/*/spec/integration/simple],
    %w[none                                         apps/web/billing/spec/integration/*_spec.rb],
    %w[unit                                         try/features],
    %w[unit                                         try/jobs],
    %w[unit                                         try/security],
    %w[unit                                         try/system],
    %w[unit                                         try/unit],
    %w[shared                                       try/support],
    %w[simple                                       try/integration/api],
    %w[simple                                       try/integration/billing],
    %w[simple                                       try/integration/boot],
    %w[simple                                       try/integration/email],
    %w[simple                                       try/integration/middleware],
    %w[simple                                       try/integration/web],
    %w[simple                                       try/integration/check_jobqueue_live_try.rb],
    %w[simple                                       try/integration/homepage_bypass_header_integration_try.rb],
    %w[simple                                       try/integration/homepage_mode_integration_try.rb],
    %w[none                                         try/integration/auth],
    %w[none                                         try/integration/authentication],
    %w[none                                         try/integration/colonel_role_auth_try.rb],
    %w[none                                         try/integration/domain_auth_enforcement_try.rb],
    %w[none                                         try/api],
    %w[none                                         try/disabled],
    %w[none                                         try/docker],
    %w[none                                         try/migrations],
    %w[none                                         try/scripts],
    %w[none                                         try/tasks],
    %w[none                                         try/web],
  ].freeze

  # Every test directory (and the individually named files) on disk. Each
  # glob has to match something: a glob that matched nothing would silently
  # drop a whole tree from the walk.
  WALK = %w[
    tests/browser/ tests/browser/*
    spec/*/ spec/integration/*/ spec/integration/full/database_triggers/*_spec.rb spec/integration/full/postgres_*_spec.rb
    apps/*/*/spec/ apps/*/*/spec/integration/*/ apps/*/*/spec/integration/*_spec.rb
    apps/*/*/spec/integration/full/migrations/*_spec.rb
    try/*/ try/integration/*/ try/integration/*_try.rb
  ].freeze

  it 'resolves every spec/ and try/ directory on disk to the lanes expected of it' do
    paths = Dir.chdir(probe.repo_root) do
      WALK.flat_map do |glob|
        found = Dir.glob(glob).map { |p| p.chomp('/') }
        expect(found).not_to be_empty, "walk glob '#{glob}' matched nothing"
        found
      end
    end.uniq - %w[spec/integration try/integration] # their children have rows

    all_lanes = probe.lanes_all
    resolved = probe.lanes_for_paths(paths)
    problems = paths.filter_map do |path|
      # `*` spans `/` in a bash `[[ == ]]` glob; File.fnmatch without
      # FNM_PATHNAME matches the same way.
      row = EXPECTED.find { |_, pattern| File.fnmatch(pattern, path) }
      next "no ownership expectation for '#{path}': add a row here and, if a lane runs it, to tests/lanes/ownership" unless row

      want = case row.first
             when 'shared' then all_lanes
             when 'none' then []
             else row.first.split(',')
             end
      got = resolved.fetch(path)
      "lanes_for_path '#{path}' = #{got} expected #{want}" unless got == want
    end
    expect(problems).to be_empty, problems.join("\n")
  end
end
