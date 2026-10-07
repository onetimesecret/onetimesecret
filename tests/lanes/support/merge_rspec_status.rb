# tests/lanes/support/merge_rspec_status.rb
#
# frozen_string_literal: true

require 'fileutils'
require 'rspec/core'

module Lanes
  # Folds the per-worker example status files of a parallel rspec run (#4551)
  # into the lane's one:
  #
  #   ruby tests/lanes/support/merge_rspec_status.rb <lane status file> <worker status glob>
  #
  # A lane run with LANES_WORKERS > 1 is N rspec processes, each started
  # through tests/lanes/support/worker-env with its own
  # LANES_RSPEC_STATUS_FILE (<run dir>/rspec-status.w<k>.txt), because
  # rspec's example_status_persistence_file_path is one file per process:
  # N processes writing one file would each merge their examples into
  # whatever the others had left there, under a lock that serializes the
  # writes but not the result. The lane's own file,
  # <run dir>/rspec-status.txt, is what `tests/lanes/run <lane> --only
  # <file> -- --only-failures` reads, so after the workers are done their
  # files are folded into it here, by lib/tasks/spec.rake, whatever the
  # run's exit status.
  #
  # The fold has rspec's own semantics (RSpec::Core::ExampleStatusMerger,
  # what one process does with its previous file): the union of the worker
  # files is "this run", the lane file is "previous runs". An example a
  # worker ran takes the worker's status; one it loaded but did not run
  # (status unknown) keeps the lane file's; one the lane file knows and no
  # worker touched is kept unless its file is gone. Entries of two worker
  # files for one example id (a spec file that loads another) are folded
  # by the same rule, in the order of the files' modification times.
  #
  # Without a worker file matching the glob the lane file is left as it is
  # and the exit status is still 0: a run that died before any worker wrote
  # its file has nothing to fold, and says so on standard output.
  module MergeRSpecStatus
    # A command line this script will not act on.
    class Error < ArgumentError; end

    WORKER_FILE = 'rspec-status.w%s.txt'
    WORKER_GLOB = WORKER_FILE % '*'

    module_function

    # The per-worker file of the lane file +lane_file+, for worker +k+.
    #
    # @return [String]
    def worker_file(lane_file, k)
      File.join(File.dirname(lane_file), WORKER_FILE % k)
    end

    # The glob matching every worker file beside the lane file.
    #
    # @return [String]
    def worker_glob(lane_file)
      File.join(File.dirname(lane_file), WORKER_GLOB)
    end

    # The worker files matching +glob+, oldest first; ties by name.
    #
    # @return [Array<String>]
    def worker_files(glob)
      Dir.glob(glob).select { |path| File.file?(path) }.sort_by { |path| [File.mtime(path), path] }
    end

    # @param lane_entries [Array<Hash>] the lane file's rows
    # @param worker_entries [Array<Array<Hash>>] one array of rows per worker file, oldest first
    # @return [Array<Hash>] the merged rows, in rspec's order
    def merge(lane_entries, worker_entries)
      this_run = worker_entries.inject([]) do |union, entries|
        RSpec::Core::ExampleStatusMerger.merge(entries, union)
      end
      RSpec::Core::ExampleStatusMerger.merge(this_run, lane_entries)
    end

    # Reads the files, merges and writes the lane file (whole, then renamed
    # into place, so a reader never sees half of it).
    #
    # @return [Hash] what was done: :workers (the files read), :examples (rows written)
    def run(lane_file, glob)
      files = worker_files(glob)
      return { workers: files, examples: nil } if files.empty?

      lane_entries   = RSpec::Core::ExampleStatusPersister.load_from(lane_file)
      worker_entries = files.map { |path| RSpec::Core::ExampleStatusPersister.load_from(path) }
      merged         = merge(lane_entries, worker_entries)

      FileUtils.mkdir_p(File.dirname(lane_file))
      scratch = "#{lane_file}.merge-#{Process.pid}"
      File.write(scratch, RSpec::Core::ExampleStatusDumper.dump(merged).to_s)
      File.rename(scratch, lane_file)
      { workers: files, examples: merged.length }
    end

    # @return [Integer] exit status
    def main(argv, out: $stdout, err: $stderr)
      raise Error, "usage: #{File.basename(__FILE__)} <lane status file> <worker status glob>" unless argv.length == 2

      lane_file, glob = argv
      done = run(lane_file, glob)
      if done.fetch(:examples)
        out.puts "merged #{done.fetch(:workers).length} worker status file(s) into #{lane_file} " \
                 "(#{done.fetch(:examples)} example statuses)"
      else
        out.puts "no worker status file matches #{glob}; #{lane_file} left as it is"
      end
      0
    rescue Error => ex
      err.puts "error: #{ex.message}"
      64
    end
  end
end

exit Lanes::MergeRSpecStatus.main(ARGV) if $PROGRAM_NAME == __FILE__
