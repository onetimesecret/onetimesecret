# tests/lanes/support/log_capture.rb
#
# frozen_string_literal: true

# The test-process side of `tests/lanes/run --capture-logs` and
# `--log-console`.
#
# The runner exports up to three names below its environment scrub:
#
#   LANES_APP_LOG_FILE=<absolute path>   application log events are appended
#                                        to this file
#   LANES_APP_LOG_CONSOLE=off|<level>    the console destination is disabled,
#                                        or held to a threshold
#   LANES_MAIL_LOG_FILE=<absolute path>  emails "delivered" by the logger
#                                        mail backend are appended to this
#                                        file instead of standard out
#
# A process that boots the application needs nothing from this file for the
# first two: spec/logging.test.yaml maps them onto the logging config's
# `destinations` block, and boot installs what the config says. This file
# covers what boot does not:
#
#   - A spec or tryout that never boots has no appender at all, so its
#     events were written nowhere. With LANES_APP_LOG_FILE set, the file
#     destination is installed as soon as the helper loads. The console is
#     left as it was: none until something boots.
#   - The logger mail backend writes outside SemanticLogger, so no logging
#     config reaches it.
#   - A value the runner should never have exported stops the process here,
#     before any test runs, instead of at the first boot or never.
#   - A write to the log file that fails later raises nothing in the
#     application. With LANES_APP_LOG_FILE set, each failed write is recorded
#     in <that path>.write-failed, which the runner looks for at the end of
#     the run and reports as an incomplete capture (exit 74).
#
# The mail file is separate on purpose. It holds raw message bodies that
# never pass the log scrubber, and the application log is not a transcript
# of everything the process printed.
#
# Loaded by spec/spec_helper.rb and try/support/test_helpers.rb, after
# `onetime` is required. With none of the three names set, install! does
# nothing.
module Lanes
  module LogCapture
    # A capture setting that cannot be honored. The message names the
    # variable and, for a file, the path.
    class Error < StandardError; end

    APP_LOG_FILE    = 'LANES_APP_LOG_FILE'
    APP_LOG_CONSOLE = 'LANES_APP_LOG_CONSOLE'
    MAIL_LOG_FILE   = 'LANES_MAIL_LOG_FILE'

    # Appended to the app log's path: the file a failed write is recorded
    # in. tests/lanes/run removes it at the start of a run and derives the
    # same name at the end.
    WRITE_FAILED_SUFFIX = '.write-failed'

    CONSOLE_OFF    = 'off'
    CONSOLE_LEVELS = %w[trace debug info warn error fatal].freeze

    # The listener watch_app_log adds: one line per failed write to the app
    # log, appended to <app log>.write-failed.
    #
    # A marker that cannot be written (the same full disk, usually) is left
    # to the application's line on standard error, which the runner also
    # looks for.
    class WriteFailureMarker
      attr_reader :app_log

      def initialize(app_log)
        @app_log = app_log
      end

      def path
        "#{app_log}#{WRITE_FAILED_SUFFIX}"
      end

      # @param file_name [String] the log file the write failed on
      # @param error [SystemCallError, IOError]
      def call(file_name, error)
        return unless file_name == app_log

        File.open(path, 'a') { |marker| marker.puts "pid #{Process.pid}: #{error.class}: #{error.message}" }
      rescue SystemCallError, IOError
        nil
      end
    end

    module_function

    # Apply the capture settings in +env+ to this process.
    #
    # Safe to call again: an unchanged log file keeps its appender and an
    # unchanged mail file keeps its handle.
    #
    # @param env [#[]] the environment to read (ENV, or a Hash in a spec)
    # @return [void]
    # @raise [Error] for an invalid value or a file that cannot be opened
    def install!(env = ENV)
      app_log = file_setting(env, APP_LOG_FILE)
      console = console_setting(env)

      if console == CONSOLE_OFF && app_log.nil?
        raise Error,
          "#{APP_LOG_CONSOLE}=off needs #{APP_LOG_FILE}: with the console off " \
          'and no log file, application log events would have no destination'
      end

      if app_log
        install_app_log(app_log)
        watch_app_log(app_log)
      end
      install_mail_log(file_setting(env, MAIL_LOG_FILE))
    end

    # install!, for a helper file loaded at the top of a test process: a
    # setting that cannot be honored ends the process with one line on
    # standard error and a non-zero status. A run that asked for a log it
    # cannot have must not go on to report success.
    #
    # @param env [#[]]
    # @return [void]
    def install_or_abort!(env = ENV)
      install!(env)
    rescue Error => ex
      abort "error: test log capture: #{ex.message}"
    end

    # The file destination alone, through the same initializer boot uses.
    #
    # The console is disabled in this config so that a process that never
    # boots keeps having no console appender. When the process does boot,
    # SetupLoggers reads the full config, finds this file destination
    # unchanged and keeps it, and adds the console the config asks for.
    def install_app_log(path)
      Onetime::Initializers::SetupLoggers.install_destinations(
        'destinations' => {
          'console' => { 'enabled' => false },
          'file' => { 'enabled' => true, 'path' => path },
        },
      )
    rescue Onetime::ConfigError => ex
      raise Error, "#{APP_LOG_FILE}: #{ex.message}"
    end

    # Record every failed write to +path+ from now on.
    #
    # The application reports an I/O error on its log file to listeners
    # (SetupLoggers::FileSink.write_failure_listeners) and on standard error.
    # The listener added here is the report that does not depend on where
    # this process's standard error goes: a spec may have replaced it, or the
    # process may be a forked child whose output a spec collects. A forked
    # child inherits the listener.
    #
    # One marker listener per process: a second call for the same path adds
    # nothing, and one for another path replaces the first.
    def watch_app_log(path)
      listeners = Onetime::Initializers::SetupLoggers::FileSink.write_failure_listeners
      return if listeners.any? { |listener| listener.is_a?(WriteFailureMarker) && listener.app_log == path }

      listeners.reject! { |listener| listener.is_a?(WriteFailureMarker) }
      listeners << WriteFailureMarker.new(path)
    end

    # Point the logger mail backend at the mail file, or leave it alone.
    #
    # Append mode, never truncated, and written through on every delivery:
    # several processes share the file (rake legs in sequence, forked
    # children at once), and a child inherits this handle as it is.
    def install_mail_log(path)
      return unless path

      require 'onetime/mail/delivery/logger'
      backend = Onetime::Mail::Delivery::Logger
      return if mail_log?(backend.output, path)

      file           = File.open(path, 'a')
      file.sync      = true
      backend.output = file
    rescue SystemCallError => ex
      raise Error,
        "#{MAIL_LOG_FILE}: cannot open the mail log #{path}: #{ex.class}: #{ex.message}. " \
        'The directory must exist and be writable.'
    end

    def mail_log?(output, path)
      output.is_a?(File) && !output.closed? && output.path == path
    end

    # @return [String, nil] 'off', a level name, or nil when unset
    def console_setting(env)
      value = env[APP_LOG_CONSOLE].to_s.strip
      return if value.empty?
      return value if value == CONSOLE_OFF || CONSOLE_LEVELS.include?(value)

      raise Error,
        "#{APP_LOG_CONSOLE} must be off or one of #{CONSOLE_LEVELS.join(', ')}"
    end

    # @return [String, nil] the path, or nil when the variable is unset
    def file_setting(env, name)
      path = env[name].to_s.strip
      return if path.empty?
      return path if File.absolute_path?(path)

      # The runner exports absolute paths. A relative one would resolve
      # against whatever directory each process happens to be in.
      raise Error, "#{name} must be an absolute path"
    end
  end
end
