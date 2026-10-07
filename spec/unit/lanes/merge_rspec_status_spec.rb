# spec/unit/lanes/merge_rspec_status_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../../../tests/lanes/support/merge_rspec_status'

# tests/lanes/support/merge_rspec_status.rb (#4551): after a lane's rspec
# invocation ran as LANES_WORKERS processes, each with its own example
# status file (tests/lanes/support/worker-env), lib/tasks/spec.rake folds
# those files into the lane's rspec-status.txt, the one `--only <file> --
# --only-failures` reads. Fixture files stand in for the three kinds of
# file; nothing here runs rspec, the runner or a rake task.
#
# The fold follows rspec's own ExampleStatusMerger: the union of the worker
# files is "this run", the lane file is "previous runs". Whether an entry of
# the lane file is kept depends on whether its spec file still exists on
# disk, which rspec checks relative to the working directory, so each
# example works in a directory of its own with the spec files it names.
RSpec.describe Lanes::MergeRSpecStatus do
  def header
    "example_id | status | run_time |\n---------- | ------ | -------- |\n"
  end

  def status_file(rows)
    header + rows.map { |id, status, time| "#{id} | #{status} | #{time || '1 second'} |\n" }.join
  end

  def parsed(path)
    RSpec::Core::ExampleStatusPersister.load_from(path).map { |row| [row[:example_id], row[:status]] }
  end

  # A directory with a run directory and the spec files the fixtures name,
  # as files so the merger finds them where the example ids say.
  def with_tree(spec_files: %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])
    Dir.mktmpdir('ots-merge-status') do |dir|
      spec_files.each do |file|
        FileUtils.mkdir_p(File.join(dir, File.dirname(file)))
        File.write(File.join(dir, file), "# fixture\n")
      end
      run_dir = File.join(dir, 'tmp', 'lanes', 'simple', 'base')
      FileUtils.mkdir_p(run_dir)
      Dir.chdir(dir) { yield run_dir, File.join(run_dir, 'rspec-status.txt') }
    end
  end

  def write_worker(run_dir, k, rows, mtime: nil)
    path = described_class.worker_file(File.join(run_dir, 'rspec-status.txt'), k)
    File.write(path, status_file(rows))
    File.utime(mtime, mtime, path) if mtime
    path
  end

  describe '.worker_file and .worker_glob' do
    # The names tests/lanes/support/worker-env gives the workers' status
    # files, beside the lane's; spec/unit/lanes/worker_env_spec.rb pins the
    # shim's side of the same names.
    it 'names worker k rspec-status.w<k>.txt beside the lane file, and the glob matches every k' do
      lane = '/x/tmp/lanes/simple/base/rspec-status.txt'

      expect(described_class.worker_file(lane, 3)).to eq('/x/tmp/lanes/simple/base/rspec-status.w3.txt')
      expect(described_class.worker_glob(lane)).to eq('/x/tmp/lanes/simple/base/rspec-status.w*.txt')
      expect(File.fnmatch(described_class.worker_glob(lane), described_class.worker_file(lane, 12))).to be(true)
      expect(File.fnmatch(described_class.worker_glob(lane), lane)).to be(false)
    end
  end

  describe '.run' do
    it 'creates the lane file from the union of the worker files, in rspec order' do
      with_tree do |run_dir, lane|
        write_worker(run_dir, 2, [['./spec/b_spec.rb[1:1]', 'passed'], ['./spec/b_spec.rb[1:2]', 'failed']])
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:2]', 'passed'], ['./spec/a_spec.rb[1:1]', 'pending']])

        done = described_class.run(lane, described_class.worker_glob(lane))

        expect(done).to eq(workers: [described_class.worker_file(lane, 1), described_class.worker_file(lane, 2)]
                                      .sort_by { |path| [File.mtime(path), path] },
                           examples: 4)
        expect(parsed(lane)).to eq([
          ['./spec/a_spec.rb[1:1]', 'pending'], ['./spec/a_spec.rb[1:2]', 'passed'],
          ['./spec/b_spec.rb[1:1]', 'passed'], ['./spec/b_spec.rb[1:2]', 'failed'],
        ])
      end
    end

    it "takes a worker's status over the lane file's for an example the worker ran" do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([['./spec/a_spec.rb[1:1]', 'failed']]))
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'passed']])

        described_class.run(lane, described_class.worker_glob(lane))

        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'passed']])
      end
    end

    it "keeps the lane file's status for an example a worker loaded but did not run" do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([['./spec/a_spec.rb[1:1]', 'failed']]))
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'unknown', '']])

        described_class.run(lane, described_class.worker_glob(lane))

        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'failed']])
      end
    end

    it 'keeps the lane file entries of files no worker loaded, while they exist' do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([
          ['./spec/a_spec.rb[1:1]', 'failed'],  # not loaded this run, file exists: kept
          ['./spec/gone_spec.rb[1:1]', 'failed'], # not loaded, file gone: dropped
        ]))
        write_worker(run_dir, 1, [['./spec/b_spec.rb[1:1]', 'passed']])

        described_class.run(lane, described_class.worker_glob(lane))

        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'failed'], ['./spec/b_spec.rb[1:1]', 'passed']])
      end
    end

    # rspec's rule: a worker that loaded the file saw every example in it,
    # so an id it did not report is an example that no longer exists.
    it 'drops a lane file entry whose file a worker loaded without that example' do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([['./spec/a_spec.rb[1:1]', 'failed'], ['./spec/a_spec.rb[1:9]', 'failed']]))
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'passed']])

        described_class.run(lane, described_class.worker_glob(lane))

        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'passed']])
      end
    end

    it 'lets the newer worker file decide when two report one example' do
      with_tree do |run_dir, lane|
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'failed']], mtime: Time.now - 60)
        write_worker(run_dir, 2, [['./spec/a_spec.rb[1:1]', 'passed']], mtime: Time.now)

        described_class.run(lane, described_class.worker_glob(lane))
        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'passed']])

        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'failed']], mtime: Time.now + 60)
        described_class.run(lane, described_class.worker_glob(lane))
        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'failed']])
      end
    end

    it 'leaves the lane file as it is, and the worker files in place, when no worker file matches' do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([['./spec/a_spec.rb[1:1]', 'failed']]))
        before = File.read(lane)

        done = described_class.run(lane, described_class.worker_glob(lane))

        expect(done).to eq(workers: [], examples: nil)
        expect(File.read(lane)).to eq(before)
        expect(Dir.children(run_dir)).to eq(['rspec-status.txt'])
      end
    end

    it 'does not read the lane file itself as a worker file' do
      with_tree do |run_dir, lane|
        File.write(lane, status_file([['./spec/a_spec.rb[1:1]', 'failed']]))
        write_worker(run_dir, 1, [['./spec/b_spec.rb[1:1]', 'passed']])

        done = described_class.run(lane, described_class.worker_glob(lane))

        expect(done.fetch(:workers)).to eq([described_class.worker_file(lane, 1)])
        expect(Dir.children(run_dir).sort).to eq(%w[rspec-status.txt rspec-status.w1.txt])
      end
    end
  end

  # The script as lib/tasks/spec.rake calls it (through .main) and as a
  # developer can: one process, the lane file and the glob as arguments.
  describe 'as a command' do
    let(:repo_root) { File.expand_path('../../..', __dir__) }
    let(:script)    { File.join(repo_root, 'tests', 'lanes', 'support', 'merge_rspec_status.rb') }

    def run_script(*args, chdir:)
      Open3.capture3({ 'BUNDLE_GEMFILE' => File.join(repo_root, 'Gemfile') },
                     'bundle', 'exec', 'ruby', script, *args, chdir: chdir)
    end

    it 'merges, reports what it did on standard output and exits 0' do
      with_tree do |run_dir, lane|
        write_worker(run_dir, 1, [['./spec/a_spec.rb[1:1]', 'passed']])
        write_worker(run_dir, 2, [['./spec/b_spec.rb[1:1]', 'failed']])

        out, err, status = run_script(lane, described_class.worker_glob(lane), chdir: Dir.pwd)

        expect(status.exitstatus).to eq(0), err
        expect(out).to eq("merged 2 worker status file(s) into #{lane} (2 example statuses)\n")
        expect(parsed(lane)).to eq([['./spec/a_spec.rb[1:1]', 'passed'], ['./spec/b_spec.rb[1:1]', 'failed']])
      end
    end

    it 'says so and exits 0 when no worker file matches' do
      with_tree do |run_dir, lane|
        glob = described_class.worker_glob(lane)

        out, err, status = run_script(lane, glob, chdir: Dir.pwd)

        expect(status.exitstatus).to eq(0), err
        expect(out).to eq("no worker status file matches #{glob}; #{lane} left as it is\n")
        expect(Dir.children(run_dir)).to be_empty
      end
    end

    it 'exits 64 with the usage for the wrong number of arguments' do
      out, err, status = run_script('only-one', chdir: repo_root)

      expect(status.exitstatus).to eq(64)
      expect(err).to include('usage: merge_rspec_status.rb <lane status file> <worker status glob>')
      expect(out).to eq('')
    end
  end
end
