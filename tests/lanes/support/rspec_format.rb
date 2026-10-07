# tests/lanes/support/rspec_format.rb
#
# frozen_string_literal: true

require 'shellwords'

module Lanes
  # The formatters one rspec invocation of a lane gets: one for the console
  # and, when a results file was asked for, the JSON one beside it.
  #
  # Two names decide, and this is the only place that reads them for rspec:
  #
  #   LANES_RSPEC_CONSOLE  `quiet` selects Lanes::QuietFormatter for the
  #                        console (tests/lanes/run --quiet exports it, below
  #                        its scrub). Unset or empty: the caller's default.
  #                        Anything else is refused.
  #   RSPEC_OUTPUT_FILE    path of the JSON results file (CI plumbing, on the
  #                        runner's keep-list). Unset or empty: no JSON.
  #
  # The two are independent. rspec replaces its whole formatter list with the
  # `--format` flags of the last option source that has any (.rspec, then the
  # command line, then SPEC_OPTS), so a console formatter chosen anywhere
  # else would drop the JSON one, or the other way round. Every invocation
  # therefore gets its complete list from here, on its command line:
  #
  #   lib/tasks/spec.rake          rspec_format_options, for every rake task
  #   tests/lanes/run --only       through the command at the end of this file
  #   tests/lanes/browser/tasks    likewise
  #
  # rspec truncates `--out` when it opens it, so two invocations of one run
  # must never be given the same path: each passes a suffix, which goes
  # between the stem and `.json`. CI collects tmp/<stem>*.json
  # (.github/actions/run-test-lane), so a suffixed file needs no change there.
  #
  # Plain Ruby with no gem behind it: the runner calls this file before
  # Bundler is involved.
  module RSpecFormat
    # An environment or argument this module will not turn into flags.
    class Error < ArgumentError; end

    CONSOLE_ENV = 'LANES_RSPEC_CONSOLE'
    RESULTS_ENV = 'RSPEC_OUTPUT_FILE'
    QUIET       = 'quiet'

    # The console formatter of a rake task that was not asked to be quiet.
    PROGRESS      = 'progress'
    # What .rspec selects, restated for an --only run that adds the JSON
    # formatter: a `--format` on the command line replaces .rspec's.
    # spec/unit/lanes/rspec_format_spec.rb pins this to the file.
    DOCUMENTATION = 'documentation'

    ONLY_SUFFIX = 'only'
    SUFFIX      = /\A[A-Za-z0-9_]+\z/

    # Absolute, so the flags do not depend on the directory rspec starts in.
    QUIET_FORMATTER = [
      '--require', File.join(__dir__, 'quiet_formatter'),
      '--format', 'Lanes::QuietFormatter'
    ].freeze

    module_function

    # @return [Boolean] whether the quiet console formatter was asked for
    # @raise [Error] for a value other than `quiet`
    def quiet?(env = ENV)
      value = env[CONSOLE_ENV].to_s
      return false if value.empty?
      return true if value == QUIET

      raise Error, "#{CONSOLE_ENV} must be '#{QUIET}' or unset, not #{value.inspect} " \
                   '(tests/lanes/run --quiet sets it)'
    end

    # @param suffix [String, nil] per-invocation discriminator
    # @return [String, nil] where this invocation writes its JSON results
    def results_file(env = ENV, suffix: nil)
      out = env[RESULTS_ENV].to_s
      return nil if out.empty?
      return out if suffix.nil?

      unless SUFFIX.match?(suffix.to_s)
        raise Error, "results file suffix #{suffix.inspect} must be letters, digits and underscores"
      end

      "#{out.delete_suffix('.json')}_#{suffix}.json"
    end

    # The complete formatter flags of one invocation, one argument per element.
    #
    # @param console [String] the console formatter when quiet was not asked for
    # @return [Array<String>]
    def argv(env = ENV, suffix: nil, console: PROGRESS)
      args = quiet?(env) ? QUIET_FORMATTER.dup : ['--format', console]
      out  = results_file(env, suffix: suffix)
      args.push('--format', 'json', '--out', out) if out
      args
    end

    # The same flags as one shell-quoted string, for a rake task's command line.
    #
    # @return [String]
    def options(env = ENV, suffix: nil)
      Shellwords.join(argv(env, suffix: suffix))
    end

    # The flags of `tests/lanes/run --only <spec files>`. None at all when
    # neither name is set: .rspec then decides, as it does for plain rspec.
    #
    # @return [Array<String>]
    def only_argv(env = ENV)
      return [] unless quiet?(env) || results_file(env)

      argv(env, suffix: ONLY_SUFFIX, console: DOCUMENTATION)
    end

    # The suffix of a rake task whose results file CI knows by its bare name.
    #
    # A lane runs such a task as the one task of its rake process, and then
    # the file keeps the name CI gave it. Run beside other tasks (an aggregate
    # such as spec:integration:all, or several names on one command line) each
    # would truncate the file the one before it wrote, so each gets a suffix
    # derived from its own name.
    #
    # @param task_name [String] full rake task name
    # @param top_level_tasks [Array<String>] the tasks rake was asked to run
    # @return [String, nil]
    def task_suffix(task_name, top_level_tasks)
      return nil if top_level_tasks == [task_name]

      task_name.delete_prefix('spec:').gsub(/[^A-Za-z0-9]+/, '_')
    end

    # `ruby tests/lanes/support/rspec_format.rb [--only]`: the flags, one
    # argument per line, for a shell caller to read into an array. No option
    # is what a rake task without a suffix gets.
    #
    # @return [Integer] exit status
    def main(args, env: ENV, out: $stdout, err: $stderr)
      flags =
        case args
        when []         then argv(env)
        when ['--only'] then only_argv(env)
        else raise Error, "usage: #{File.basename(__FILE__)} [--only]"
        end
      if flags.any? { |flag| flag.include?("\n") }
        raise Error, "#{RESULTS_ENV} contains a line break and cannot be passed one argument per line"
      end

      out.puts(flags) unless flags.empty?
      0
    rescue Error => ex
      err.puts "error: #{ex.message}"
      64
    end
  end
end

exit Lanes::RSpecFormat.main(ARGV) if $PROGRAM_NAME == __FILE__
