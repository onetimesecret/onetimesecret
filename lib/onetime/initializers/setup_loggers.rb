# lib/onetime/initializers/setup_loggers.rb
#
# frozen_string_literal: true

require 'yaml'
require 'date' # ensure Date/Time constants resolve for permitted_classes
require 'semantic_logger'
require_relative '../utils/config_resolver'
require_relative '../utils/enumerables'
require_relative '../log_scrubber'

module Onetime
  module Initializers
    # Configures SemanticLogger with strategic categories for debugging.
    #
    # Categories: App, Auth, Billing, Boot, Bunny, Ents, Familia, HTTP, Jobs,
    # Org, Otto, Rhales, Scheduler, Secret, Sequel, Session, Workers.
    #
    # Chores and CLI are logger names the application uses, and the shipped
    # config lists a level for each, but they are not categories here (see
    # UNAPPLIED_CONFIG_CATEGORIES): both run at the default level.
    #
    # Configuration loaded from etc/logging.yaml with environment variable
    # overrides. Logger instances are cached because SemanticLogger[]
    # creates new instances on each call.
    #
    # Two separate controls decide what is written where:
    #
    #   Category levels (`loggers:`, LOG_LEVEL, DEBUG_*) decide which events
    #   are generated at all.
    #
    #   Destinations (`destinations:` — console and file) each write the
    #   generated events that pass their own optional threshold. A destination
    #   cannot recover an event its category rejected.
    #
    # Environment variables:
    #   LOG_LEVEL        - Global default level (trace/debug/info/warn/error/fatal)
    #   ONETIME_DEBUG    - Sets global default to debug when truthy
    #   BACKTRACE_LEVEL  - Level at which backtraces are included (default: error)
    #   BACKTRACE_LINES  - Max exception backtrace lines on the console (default: unlimited)
    #   DEBUG_*          - Per-category debug flags (e.g., DEBUG_AUTH=1)
    #   DEBUG_LOGGERS    - Fine-grained control (e.g., "Auth:debug,Secret:trace")
    #
    # Runtime state set:
    #   Onetime::Runtime.infrastructure.cached_loggers
    #
    class SetupLoggers < Onetime::Boot::Initializer
      # SemanticLogger category the operator audit sink emits on (#4334).
      #
      # A literal, not Onetime::ColonelAuditEvent::SINK_LOGGER_NAME, because
      # this initializer runs in the :fork_sensitive boot phase — before the
      # models are loaded — and referencing the constant there would raise
      # NameError into the appender's rescue and silently disable the operator's
      # configured audit destination. The two MUST agree; a spec pins that
      # (spec/unit/onetime/models/colonel_audit_event_spec.rb).
      AUDIT_SINK_LOGGER_NAME = 'ColonelAudit'

      # Exact-name filter for the audit syslog appender. SemanticLogger matches
      # `filter` against the logger NAME, and a loose pattern would quietly
      # start copying unrelated categories into the operator's audit
      # destination.
      AUDIT_SINK_FILTER = /\A#{Regexp.escape(AUDIT_SINK_LOGGER_NAME)}\z/

      @provides           = [:logging].freeze
      @phase              = :fork_sensitive
      @logger_definitions = {
        'App' => 'DEBUG_APP',
        'Auth' => 'DEBUG_AUTH',
        'Billing' => 'DEBUG_BILLING',
        'Boot' => 'DEBUG_BOOT',
        'Bunny' => 'DEBUG_BUNNY',
        'Ents' => 'DEBUG_ENTS',
        'Familia' => 'DEBUG_FAMILIA',
        'HTTP' => 'DEBUG_HTTP',
        'Jobs' => 'DEBUG_JOBS',
        'Org' => 'DEBUG_ORG',
        'Otto' => 'DEBUG_OTTO',
        'Rhales' => 'DEBUG_RHALES',
        'Scheduler' => 'DEBUG_SCHEDULER',
        'Secret' => 'DEBUG_SECRET',
        'Sequel' => 'DEBUG_SEQUEL',
        'Session' => 'DEBUG_SESSION',
        'Workers' => 'DEBUG_WORKERS',
      }.freeze

      # Categories the shipped logging config names under `loggers:` whose
      # level this initializer does not apply.
      #
      # Chores and CLI have been listed at info since they were added to the
      # config, but were never in logger_definitions, so both have always run
      # at the default level (warn, or LOG_LEVEL). Applying the listed level
      # would make a default `bin/ots` command print its info lines on stderr
      # and add Chores info lines to server output: a change to the default
      # output, which needs its own decision and release note. Until then
      # this records the gap, and a spec keeps it from growing
      # (spec/unit/onetime/initializers/setup_loggers_spec.rb).
      # DEBUG_LOGGERS=CLI:info sets either one for a run.
      UNAPPLIED_CONFIG_CATEGORIES = %w[Chores CLI].freeze

      # An appender this initializer added, with the settings it was built
      # from. `identity` is compared on a rerun to tell an unchanged
      # destination from a changed one.
      OwnedAppender = Data.define(:appender, :identity)

      # SemanticLogger's file appender with a working #close.
      #
      # The stock appender (4.18) inherits Subscriber#close, a no-op, so
      # SemanticLogger.remove_appender would leave the replaced file open
      # until garbage collection. A closed sink that is logged to again
      # reopens its file, as the stock appender does on first use.
      #
      # It also reports a write that fails. SemanticLogger rescues whatever an
      # appender raises and mentions it once per event on its internal logger
      # ("Failed to log to appender"), in the same words for a full disk as
      # for a thread that was interrupted while logging. An I/O error on the
      # log file is the one that loses events from then on, so #log says so
      # itself: one line on standard error per process, and a call to each
      # listener, for SystemCallError and IOError only. The error is raised
      # again, so SemanticLogger handles it as it always has.
      class FileSink < SemanticLogger::Appender::File
        # Start of the line printed on standard error; the file's path and
        # the error follow. The lane runner looks for it (tests/lanes/run).
        WRITE_FAILURE_PREFIX = '[SetupLoggers] Cannot write to the log file'

        @write_failure_listeners = []

        class << self
          # Callables run with (file_name, exception) on every failed write,
          # on the thread that was writing. Add one with <<.
          #
          # @return [Array<#call>]
          attr_reader :write_failure_listeners
        end

        def log(log)
          super
        rescue SystemCallError, IOError => ex
          report_write_failure(ex)
          raise
        end

        def close
          @file&.close
        rescue IOError
          nil
        ensure
          @file = nil
        end

        private

        # Reporting must not replace the write error it reports, so nothing
        # raised here leaves this method.
        def report_write_failure(error)
          unless @write_failure_reported_in == Process.pid
            @write_failure_reported_in = Process.pid
            # Not Kernel#warn: that prints nothing under -W0.
            $stderr.write(
              "#{WRITE_FAILURE_PREFIX} #{file_name}: #{error.class}: #{error.message}. " \
              "Log events are being lost. Reported once per process.\n",
            )
          end
          self.class.write_failure_listeners.each { |listener| listener.call(file_name, error) }
        rescue StandardError
          nil
        end
      end

      # role (:console, :file) => OwnedAppender. Process-wide, like the
      # SemanticLogger appender list it describes: every instance of this
      # initializer reconciles against the same record.
      @owned_appenders = {}

      class << self
        attr_reader :logger_definitions, :owned_appenders

        # Install the configured log destinations in a process that does not
        # run boot (a spec helper, a script). See #install_destinations.
        #
        # @param config [Hash, nil] logging config; nil loads the resolved
        #   logging config files, as boot does
        # @return [void]
        def install_destinations(config = nil)
          initializer = new
          config.nil? ? initializer.install_destinations : initializer.install_destinations(config)
        end
      end

      def execute(_context)
        # First, before any appender exists: the global URI scrub runs as an
        # on_log subscriber, ahead of every appender (Onetime::LogScrubber).
        # boot! registers it earlier; this idempotent call covers the
        # initializer running outside boot!, as in specs.
        Onetime::LogScrubber.register!

        @debug_boot          = OT::Utils.yes?(ENV.fetch('DEBUG_BOOT', nil))
        config               = load_logging_config
        Onetime.logging_conf = config

        SemanticLogger.application = 'onetimesecret'

        configure_default_level(config)
        install_destinations(config)

        cached_loggers = create_cached_loggers(config)
        apply_env_overrides(cached_loggers)
        configure_external_loggers(cached_loggers)

        log_effective_configuration(cached_loggers) if Onetime.debug?
        Onetime::Runtime.update_infrastructure(cached_loggers: cached_loggers)
      end

      # Cleanup SemanticLogger before fork.
      # Called by InitializerRegistry.cleanup_before_fork from Puma's before_fork hook.
      #
      # Flushes async appender to prevent lost log messages. The async appender
      # queues messages in a background thread that won't survive fork.
      #
      # @return [void]
      def cleanup
        SemanticLogger.flush if defined?(SemanticLogger)
      rescue StandardError => ex
        warn "[SetupLoggers] Error during cleanup: #{ex.message}"
      end

      # Reconnect SemanticLogger after fork.
      # Called by InitializerRegistry.reconnect_after_fork from fork hooks (Puma, Sneakers).
      #
      # Re-opens appenders to create fresh async processing threads, replacing
      # zombie thread references inherited from the master process.
      #
      # @return [void]
      def reconnect
        SemanticLogger.reopen if defined?(SemanticLogger)
      rescue StandardError => ex
        warn "[SetupLoggers] Error during reconnect: #{ex.message}"
      end

      # Bring the appenders in line with the logging config: the console and
      # file destinations from the `destinations` block, and the optional
      # audit syslog appender.
      #
      # This is all of the initializer's appender handling and nothing else:
      # category levels, the default level and the external-library loggers
      # are left alone. It is safe to call again. An unchanged destination is
      # kept (no duplicate), a changed one is replaced (no stale file path),
      # and an appender this initializer did not add is never touched.
      #
      # @param config [Hash] logging config (string keys, as loaded from YAML)
      # @return [void]
      # @raise [Onetime::ConfigError] for an invalid destination setting, a
      #   log file that cannot be opened, or a configuration that leaves audit
      #   events without any destination
      def install_destinations(config = load_logging_config)
        Onetime::LogScrubber.register!

        # Both are read and validated before any appender changes. The
        # console goes first, so that it is in place to show the error when
        # the log file cannot be opened.
        console = console_destination(config)
        file    = file_destination(config)

        configure_console_appender(console)
        configure_file_appender(file)
        configure_audit_syslog_appender(config)
        ensure_audit_destination!
      end

      private

      def load_logging_config
        defaults_file = Onetime::Utils::ConfigResolver.defaults_path('logging')
        override_file = Onetime::Utils::ConfigResolver.resolve('logging')

        # safe_load prevents a malicious logger config from instantiating
        # arbitrary Ruby objects; Symbol is permitted because log levels and
        # category keys are symbols. Date and Time are permitted so an
        # unquoted date/time in a logging config loads as a Date/Time instance
        # rather than raising Psych::DisallowedClass and breaking boot (per
        # issue #3498). aliases: true keeps YAML anchors working for shared
        # formatter/appender settings.
        base_config = if defaults_file
          YAML.safe_load(ERB.new(File.read(defaults_file)).result, permitted_classes: [Symbol, Date, Time], aliases: true) || {}
        else
          {}
        end

        env_config = if override_file && override_file != defaults_file
          YAML.safe_load(ERB.new(File.read(override_file)).result, permitted_classes: [Symbol, Date, Time], aliases: true) || {}
        else
          {}
        end

        return base_config if env_config.empty?
        return env_config if base_config.empty?

        Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
      end

      # Precedence: LOG_LEVEL env > ONETIME_DEBUG > config file > :info default
      def configure_default_level(config)
        SemanticLogger.default_level = ENV['LOG_LEVEL']&.to_sym ||
                                       config['default_level']&.to_sym ||
                                       :info

        SemanticLogger.default_level   = :debug if Onetime.debug?
        SemanticLogger.backtrace_level = ENV['BACKTRACE_LEVEL']&.to_sym || :error
      end

      # The console destination: one appender on stdout, or on stderr under
      # the CLI (see #log_device).
      #
      # A console appender that someone else added — a tryout's
      # `add_appender(io: $stdout)` — already is the console. SemanticLogger
      # refuses a second one, so ours is left out rather than requested and
      # refused with a warning.
      #
      # @param destination [Hash, nil] from #console_destination; nil = disabled
      def configure_console_appender(destination)
        destination = nil if destination && foreign_console_appender?

        reconcile(:console, destination) do
          SemanticLogger::Appender.factory(
            io: log_device,
            formatter: truncating_formatter(destination[:formatter], destination[:backtrace_lines]),
            filter: destination_filter(destination[:level]),
          )
        end
      end

      # The file destination: every admitted event, appended to one file.
      #
      # The file is opened here, not on the first event. SemanticLogger opens
      # lazily, does not create directories, and reports a failed write only
      # on stderr; a log file that was asked for and cannot be written must
      # stop setup instead.
      #
      # @param destination [Hash, nil] from #file_destination; nil = disabled
      def configure_file_appender(destination)
        reconcile(:file, destination) do
          # Never truncated: several processes may append to the same file
          # (a forked server, test processes run in sequence). Each line is
          # one write on an O_APPEND handle.
          sink = FileSink.new(
            destination[:path],
            append: true,
            formatter: destination[:formatter],
            filter: destination_filter(destination[:level]),
          )
          open_file_sink(sink)
        end
      end

      def open_file_sink(sink)
        sink.reopen
        sink
      rescue SystemCallError, IOError, ArgumentError => ex
        raise Onetime::ConfigError,
          "Cannot open the log file #{sink.file_name} (logging destinations.file.path): " \
          "#{ex.class}: #{ex.message}. The directory must exist and be writable."
      end

      # Make the appender list match one destination's settings.
      #
      # The replacement is built by the block BEFORE the current appender is
      # removed, so a destination that cannot be built raises with the current
      # one still in place.
      #
      # @param role [Symbol] :console or :file
      # @param wanted [Hash, nil] the destination's settings; nil = disabled
      # @yieldreturn [SemanticLogger::Subscriber] the appender for `wanted`
      def reconcile(role, wanted)
        owned = owned_appender(role)
        return if owned&.identity == wanted

        replacement = yield if wanted

        if owned
          self.class.owned_appenders.delete(role)
          SemanticLogger.remove_appender(owned.appender) # removes and closes
        end
        return unless replacement && SemanticLogger.add_appender(appender: replacement)

        self.class.owned_appenders[role] = OwnedAppender.new(appender: replacement, identity: wanted)
      end

      # The appender this initializer added for a role, if SemanticLogger
      # still has it. A record whose appender was removed behind our back
      # (SemanticLogger.close, clear_appenders!) is dropped, and the appender
      # closed, so the next reconcile adds a fresh one.
      def owned_appender(role)
        owned = self.class.owned_appenders[role]
        return unless owned
        return owned if SemanticLogger.appenders.any? { |appender| appender.equal?(owned.appender) }

        self.class.owned_appenders.delete(role)
        owned.appender.close
        nil
      end

      def owned_appender?
        [:console, :file].any? { |role| owned_appender(role) }
      end

      def foreign_console_appender?
        ours = owned_appender(:console)&.appender
        SemanticLogger.appenders.any? do |appender|
          !appender.equal?(ours) && appender.respond_to?(:console_output?) && appender.console_output?
        end
      end

      def audit_syslog_appender?
        # Matched by class NAME: the constant is only defined once
        # add_appender has loaded the appender file.
        SemanticLogger.appenders.any? { |appender| appender.class.name.to_s.end_with?('Appender::Syslog') }
      end

      # Settings of the console destination, or nil when it is disabled.
      #
      # The stream is recorded by name, not by object: a spec that swaps
      # $stdout for a StringIO around a command must not make a rerun move
      # the appender onto that temporary object.
      def console_destination(config)
        return unless destination_enabled?(config, 'console', default: true)

        {
          stream: console_stream,
          level: destination_level(config, 'console'),
          formatter: destination_formatter(config, 'console') || default_console_formatter(config),
          backtrace_lines: backtrace_limit,
        }
      end

      # Settings of the file destination, or nil when it is disabled.
      #
      # A relative path is resolved against the application root, so the file
      # does not depend on the directory the process was started from.
      def file_destination(config)
        return unless destination_enabled?(config, 'file', default: false)

        path = destination_settings(config, 'file')['path'].to_s.strip
        if path.empty?
          raise Onetime::ConfigError,
            'logging destinations.file.enabled is true but destinations.file.path is not set'
        end

        {
          path: File.expand_path(path, Onetime::HOME),
          level: destination_level(config, 'file'),
          # Plain text unless told otherwise: a file is not a terminal.
          formatter: destination_formatter(config, 'file') || :default,
        }
      end

      def destination_settings(config, role)
        settings = config.dig('destinations', role)
        settings.is_a?(Hash) ? settings : {}
      end

      def destination_enabled?(config, role, default:)
        Onetime::Utils::Strings.strict_bool!(
          "logging destinations.#{role}.enabled",
          destination_settings(config, role)['enabled'],
          default: default,
        )
      end

      # @return [Symbol, nil] the destination's threshold; nil = none
      def destination_level(config, role)
        level = destination_settings(config, role)['level'].to_s.strip.downcase
        return if level.empty?
        return level.to_sym if SemanticLogger::Levels::LEVELS.include?(level.to_sym)

        raise Onetime::ConfigError,
          "logging destinations.#{role}.level is not a log level. " \
          "Use one of #{SemanticLogger::Levels::LEVELS.join('/')}, or leave it unset for no threshold."
      end

      # @return [Symbol, nil] the destination's own formatter; nil = unset
      def destination_formatter(config, role)
        formatter = destination_settings(config, role)['formatter'].to_s.strip
        return if formatter.empty?

        SemanticLogger::Formatters.factory(formatter.to_sym)
        formatter.to_sym
      rescue ArgumentError
        raise Onetime::ConfigError,
          "logging destinations.#{role}.formatter is not a known formatter. " \
          'Use color, json or default, or leave it unset.'
      end

      # A destination threshold, as an appender filter.
      #
      # A filter rather than the appender's own `level:` because audit events
      # must pass: ColonelAudit emits at info, and a console held to warn for
      # quiet output would otherwise drop the audit stream from the one place
      # it is written by default.
      #
      # @param level [Symbol, nil]
      # @return [Proc, nil] nil = no threshold, the appender takes everything
      def destination_filter(level)
        return unless level

        floor = SemanticLogger::Levels.index(level)
        ->(log) { log.name == AUDIT_SINK_LOGGER_NAME || (log.level_index || 0) >= floor }
      end

      # Audit events must always have somewhere to go.
      #
      # Onetime::ColonelAuditEvent writes each event to the log BEFORE it
      # writes it to Valkey; that line is the durable copy. With the console
      # and the file both disabled and no audit syslog appender, it would be
      # written nowhere, and nothing at runtime would say so.
      def ensure_audit_destination!
        return if owned_appender? || foreign_console_appender? || audit_syslog_appender?

        raise Onetime::ConfigError,
          'Logging has no destination for audit events: destinations.console and ' \
          'destinations.file are both disabled and the audit syslog appender is not active. ' \
          'Enable at least one of them.'
      end

      # OPTIONAL syslog appender for the operator audit sink (#4334).
      #
      # Onetime::ColonelAuditEvent emits every audit event as a structured log
      # line on the dedicated `ColonelAudit` category BEFORE writing it to
      # Valkey — that stream, not the capped sorted set, is the durability
      # story. By default it rides the console appender above (stdout, which
      # container log collectors already read). Operators who need the audit
      # stream shipped SEPARATELY from application logs — a SIEM, a write-once
      # host, its own retention — enable this.
      #
      # DEFAULT OFF, and no third-party dependency for the default URL:
      # SemanticLogger ships the syslog appender in-gem, and `syslog://` (the
      # local daemon) speaks through Ruby's own `syslog` library — declared in
      # the Gemfile's stdlib section because Ruby 3.4 made it a bundled gem.
      # A `tcp://` / `udp://` URL ships to a REMOTE syslog server and needs the
      # third-party `syslog_protocol` gem, which this repo does not bundle; the
      # rescue below turns that into one warning at boot rather than a failed
      # start.
      #
      # FILTERED to the audit category ({AUDIT_SINK_FILTER}), so enabling it
      # ships the audit stream and nothing else.
      #
      # Idempotent: test reruns and re-executed initializers must not stack
      # duplicate appenders.
      def configure_audit_syslog_appender(config)
        settings = config.dig('audit', 'syslog') || {}
        return unless OT::Utils.yes?(settings['enabled'])
        return if audit_syslog_appender?

        require 'syslog'

        SemanticLogger.add_appender(
          appender: :syslog,
          url: settings['url'].to_s.empty? ? 'syslog://localhost' : settings['url'].to_s,
          level: (settings['level'] || 'info').to_sym,
          facility: syslog_facility(settings['facility']),
          level_map: syslog_level_map,
          filter: AUDIT_SINK_FILTER,
        )
      rescue StandardError, LoadError => ex
        # Never fail boot over an optional log destination. The sink still
        # reaches the console or file destination, so the audit stream is not
        # lost — only its second copy is. When neither of those is enabled,
        # ensure_audit_destination! fails setup.
        warn "[SetupLoggers] audit syslog appender not enabled: #{ex.class}: #{ex.message}"
      end

      # Resolve a syslog facility NAME (local0, daemon, authpriv, …) to the
      # ::Syslog integer constant the appender wants. Config carries the name
      # because an operator writes `facility: local0`, not a bitmask.
      #
      # Anything unrecognised falls back to LOG_USER rather than raising: a
      # typo in a logging config must not cost the audit sink its second
      # destination. const_get is bounded to LOG_-prefixed names on ::Syslog,
      # so a config value can never reach an arbitrary constant.
      def syslog_facility(name)
        candidate = "LOG_#{name.to_s.strip.upcase}"
        return ::Syslog::LOG_USER unless candidate.match?(/\ALOG_[A-Z0-9]+\z/) && ::Syslog.const_defined?(candidate)

        ::Syslog.const_get(candidate)
      end

      # SemanticLogger level → syslog severity, supplied EXPLICITLY.
      #
      # Not a nicety: the appender's `level_map:` default value is
      # `SemanticLogger::Formatters::Syslog::LevelMap.new`, and merely
      # evaluating that default autoloads a formatter file whose first line is
      # `require "syslog_protocol"` — so omitting this argument makes even the
      # LOCAL `syslog://` case demand a remote-logging gem we do not bundle.
      # Passing a plain Hash (which the appender indexes with `[]`, same as a
      # LevelMap) keeps the local path dependency-free.
      #
      # The values mirror the gem's documented defaults; syslog severities are
      # fixed by RFC 5424, so there is nothing here that drifts.
      #
      # A method rather than a constant: ::Syslog is only required when the
      # appender is actually being enabled, so a constant would have to resolve
      # those values at class-definition time.
      def syslog_level_map
        {
          trace: ::Syslog::LOG_DEBUG,
          debug: ::Syslog::LOG_INFO,
          info: ::Syslog::LOG_NOTICE,
          warn: ::Syslog::LOG_WARNING,
          error: ::Syslog::LOG_ERR,
          fatal: ::Syslog::LOG_CRIT,
        }.freeze
      end

      # Where console logs go.
      #
      # Server modes log to stdout, which is what container runtimes and log
      # collectors read. A CLI cannot: stdout is its data channel — `--json`
      # output, piped listings, anything a caller parses. Boot diagnostics
      # sharing that stream corrupt it, and the caller has no way to tell a log
      # line from a result. Diagnostics are not the command's output, so in CLI
      # mode they go to stderr.
      #
      # @return [IO]
      def log_device
        console_stream == :stderr ? $stderr : $stdout
      end

      # @return [Symbol] :stderr under the CLI, :stdout otherwise
      def console_stream
        OT.mode?(:cli) ? :stderr : :stdout
      end

      # Build the console formatter, with the exception backtrace limit when
      # one is set.
      #
      # Backtraces are written in full unless BACKTRACE_LINES is set. With it,
      # only the console is shortened: the file destination always writes the
      # whole backtrace, and error tracking (Sentry) is not affected.
      #
      # Environment variables:
      #   BACKTRACE_LINES - Max backtrace lines on the console (default: unlimited)
      #
      def build_formatter(config)
        truncating_formatter(default_console_formatter(config), backtrace_limit)
      end

      # The console formatter when destinations.console.formatter is unset:
      # color under the CLI, the top-level `formatter` setting otherwise.
      def default_console_formatter(config)
        if OT.mode?(:cli)
          :color # Human-readable for CLI
        else
          config['formatter']&.to_sym || :color
        end
      end

      # @param base_formatter [Symbol] a SemanticLogger formatter name
      # @param max_lines [Integer, nil] backtrace limit; nil = unlimited
      # @return [Symbol, Proc]
      def truncating_formatter(base_formatter, max_lines)
        # No limit: the standard formatter, full backtraces
        return base_formatter unless max_lines

        # A limit: wrap the formatter to truncate exception backtraces
        formatter = SemanticLogger::Formatters.factory(base_formatter)
        proc do |log, logger|
          formatter.call(with_truncated_backtrace(log, max_lines), logger)
        end
      end

      # The console backtrace line limit: BACKTRACE_LINES, and nothing else.
      #
      # There is no per-environment default. This method once named a 3-line
      # production default, but compared Onetime.mode (the entry point: :app,
      # :cli, ...) to 'production', which never matched, so production has
      # always logged full backtraces. Starting to truncate them would change
      # what a default deployment prints; an operator who wants the short form
      # sets BACKTRACE_LINES.
      #
      # @return [Integer, nil] Max lines, or nil for unlimited
      def backtrace_limit
        ENV['BACKTRACE_LINES'].to_i if ENV['BACKTRACE_LINES']
      end

      # The event this formatter renders: the Log itself when its exception's
      # backtrace is within the limit, otherwise a copy carrying a copy of the
      # exception with the shortened backtrace.
      #
      # Nothing is truncated in place. SemanticLogger hands the same Log to
      # every appender, and the exception (with its backtrace Array) belongs
      # to the caller, who may still re-raise it or report it to Sentry.
      # Truncating here must not shorten what they see.
      #
      # clone rather than dup: Onetime::LogScrubber's exception copies carry
      # their scrubbed text in singleton methods, which dup drops.
      #
      # Only the outermost exception is shortened; a cause keeps its backtrace.
      def with_truncated_backtrace(log, max_lines)
        backtrace = log.exception&.backtrace
        return log unless backtrace && backtrace.size > max_lines

        exception = log.exception.clone(freeze: false)
        exception.set_backtrace(backtrace.first(max_lines) << "... (#{backtrace.size - max_lines} more lines)")

        log.dup.tap { |copy| copy.exception = exception }
      end

      # Create and cache logger instances with levels from config.
      #
      # Only the categories in logger_definitions. A name the config lists
      # under `loggers:` that is not defined there gets no logger here and no
      # level (see UNAPPLIED_CONFIG_CATEGORIES).
      def create_cached_loggers(config)
        self.class.logger_definitions.each_with_object({}) do |(name, _), cache|
          level        = config.dig('loggers', name)&.to_sym || SemanticLogger.default_level
          warn " initialize #{name}=#{level}" if @debug_boot
          logger       = SemanticLogger[name]
          logger.level = level
          cache[name]  = logger
        end
      end

      # Apply DEBUG_* flags and DEBUG_LOGGERS overrides
      def apply_env_overrides(cached_loggers)
        # DEBUG_* flags set logger to debug level
        self.class.logger_definitions.each do |name, env_var|
          next unless OT::Utils.yes?(ENV[env_var])

          cached_loggers[name].level = :debug
        end

        # DEBUG_LOGGERS=Auth:debug,Secret:trace for fine-grained control
        ENV['DEBUG_LOGGERS']&.split(',')&.each do |spec|
          name, level = spec.split(/[:=]/, 2).map(&:strip)
          next unless name && level

          (cached_loggers[name] ||= SemanticLogger[name]).level = level.to_sym
        end
      end

      # Wire up external libraries to use our cached loggers
      def configure_external_loggers(cached_loggers)
        Familia.logger = cached_loggers['Familia']
        Otto.logger    = cached_loggers['Otto']
        Otto.debug     = Onetime.debug?

        configure_familia_hooks
      end

      # Register Familia hooks for Redis command and lifecycle logging.
      # Uses sampling in production to reduce volume.
      def configure_familia_hooks
        return unless defined?(Familia::DatabaseLogger)

        Familia::DatabaseLogger.sample_rate = case Onetime.conf[:environment]
        when 'production' then ENV['FAMILIA_SAMPLE_RATE']&.to_f || 0.01
        when 'development' then ENV['FAMILIA_SAMPLE_RATE']&.to_f || 1.0
        end

        if Familia.respond_to?(:on_command)
          Familia.on_command do |cmd, duration, context|
            Familia.logger.debug 'Redis command',
              command: cmd,
              duration: duration,
              context: context
          end
        end

        return unless Familia.respond_to?(:on_lifecycle)

        Familia.on_lifecycle do |event, instance, context|
          Familia.logger.debug 'Familia lifecycle',
            event: event,
            class: instance.class.name,
            identifier: instance.respond_to?(:identifier) ? instance.identifier : nil,
            context: context
        end
      end

      def log_effective_configuration(cached_loggers)
        default   = SemanticLogger.default_level
        overrides = cached_loggers.filter_map do |name, logger|
          "#{name}=#{logger.level}" if logger.level != default
        end
        if Onetime.debug?
          warn " default=#{default}, overrides: #{overrides.any? ? overrides.join(', ') : '(none)'}"
        end
      end
    end
  end
end
