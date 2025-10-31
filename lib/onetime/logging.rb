# lib/onetime/logging.rb

require 'reline' # stdlib

module Onetime
  # Category-aware logging support for Onetime classes and modules.
  #
  # Provides access to SemanticLogger instances scoped to strategic categories:
  # Auth, Session, HTTP, Familia, Otto, Rhales, Secret, App (default).
  #
  # Usage in classes:
  #   class MyAuthController
  #     include Onetime::Logging
  #
  #     def login
  #       auth_logger.info "Login attempt", email: email, ip: request.ip
  #       # ...
  #     end
  #   end
  #
  # Usage with automatic category detection:
  #   class V2::Logic::Authentication::AuthenticateSession
  #     include Onetime::Logging
  #
  #     def perform
  #       logger.debug "Validating credentials"  # Uses 'Authentication' logger
  #       # ...
  #     end
  #   end
  #
  # Thread-local category override:
  #   def handle_request
  #     with_log_category('HTTP') do
  #       logger.info "Processing request"  # Uses 'HTTP' logger
  #     end
  #   end
  #
  module Logging
    # Returns a SemanticLogger instance scoped to the current class.
    # Attempts to extract a meaningful category from the class name,
    # falling back to 'App' if no match found.
    #
    # @return [SemanticLogger] Logger instance for this class
    #
    def logger
      category = Thread.current[:log_category] || infer_category

      # During early boot before Initializers is extended, get_logger won't exist yet
      # Fall back to uncached logger for early logging, switch to cached after boot
      Onetime.get_logger(category)
    end

    # Access a cached logger instance by name
    # Returns the pre-configured logger with the correct level set
    #
    # @param name [String, Symbol] Logger category name
    # @return [SemanticLogger::Logger] Cached logger instance
    #
    def get_logger(name)
      @cached_loggers ||= {}
      @cached_loggers[name.to_s] ||= SemanticLogger[name.to_s]
    end

    # Box drawing helper for formatted log output.
    #
    # Creates visually distinct boxed messages using Unicode box-drawing characters.
    # Automatically handles line width calculations and padding for clean alignment.
    #
    # @param lines [Array<String>] Lines to display in the box (excluding border)
    # @param width [Integer] Total internal width of the box (default: 56)
    # @param logger_method [Symbol] Logger method to use (:li, :ld, :lw, :le)
    #
    # @example Simple box
    #   Onetime.log_box(['Hello, world!'])
    #   # ╔════════════════════════════════════════════════════════╗
    #   # ║ Hello, world!                                          ║
    #   # ╚════════════════════════════════════════════════════════╝
    #
    # @example Multi-line with custom width
    #   Onetime.log_box([
    #     '✅ DATABASE: Connected 7 models to Redis',
    #     '   Location: redis:6379/0'
    #   ])
    #
    # @example Different log levels
    #   Onetime.log_box(['⚠️  Warning message'], logger_method: :lw)
    #   Onetime.log_box(['Debug info'], logger_method: :ld)
    #
    def log_box(lines, width: 52, logger_method: :boot_logger, level: :info)
      # Box drawing characters
      top_left     = '╭'  # or: ┏ ┌ ┍ ┎ ┱ ┲ ╒ ╓ ╭ ╔
      top_right    = '╮'  # or: ┓ ┐ ┑ ┒ ┳ ┴ ╕ ╖ ╮ ╗
      bottom_left  = '╰'  # or: ┗ └ ┕ ┖ ┹ ┺ ╘ ╙ ╰ ╚
      bottom_right = '╯'  # or: ┛ ┘ ┙ ┚ ┻ ┼ ╛ ╜ ╯ ╝
      horizontal   = '─'  # or: ─ ━ ┄ ┅ ┈ ┉ ╌ ╍ ═ ═
      vertical     = '│'  # or: │ ┃ ┆ ┇ ┊ ┋ ╎ ╏ ║ ║

      # Build the box
      top_border = top_left + (horizontal * width) + top_right
      bottom_border = bottom_left + (horizontal * width) + bottom_right
      lager = send(logger_method)

      # Output the box (note: no protection against overly long lines)
      lager.send(level, top_border)
      lines.each do |it|
        padding = width - Reline::Unicode.calculate_width(it) - 2
        padding = 0 if padding.negative?
        lager.send(level, "#{vertical} #{it}#{' ' * (padding)} #{vertical}")
      end
      lager.send(level, bottom_border)
    end

    # Category-specific logger accessors for explicit context
    # Uses cached logger instances from Onetime::Initializers to preserve level settings
    # Falls back to uncached loggers during early boot before get_logger is available
    def app_logger
      Onetime.get_logger('App')
    end

    def boot_logger
      Onetime.get_logger('Boot')
    end

    def auth_logger
      Onetime.get_logger('Auth')
    end

    def familia_logger
      Onetime.get_logger('Familia')
    end

    def http_logger
      Onetime.get_logger('HTTP')
    end

    def otto_logger
      Onetime.get_logger('Otto')
    end

    def rhales_logger
      Onetime.get_logger('Rhales')
    end

    def secret_logger
      Onetime.get_logger('Secret')
    end

    def session_logger
      Onetime.get_logger('Session')
    end

    def sequel_logger
      Onetime.get_logger('Sequel')
    end

    # Execute block with a specific log category via thread-local variable.
    #
    # Enables shared utilities and cross-cutting concerns to log under
    # appropriate operational categories without coupling to specific loggers.
    # Thread-safe - each request/thread maintains independent category context.
    #
    # @param category [String, Symbol] The log category to use
    # @yield Block to execute with the specified category
    #
    # @example Cross-cutting concerns logging under appropriate categories
    #   class RequestProcessor
    #     def handle_auth_request
    #       with_log_category('Auth') do
    #         logger.info "Processing authentication"  # → Auth logs
    #       end
    #     end
    #
    #     def handle_session_request
    #       with_log_category('Session') do
    #         logger.info "Processing session"  # → Session logs
    #       end
    #     end
    #   end
    #
    def with_log_category(category)
      old_category                  = Thread.current[:log_category]
      Thread.current[:log_category] = category.to_s
      yield
    ensure
      Thread.current[:log_category] = old_category
    end

    private

    # Infer log category from class name by checking for known patterns.
    #
    # Maps class names to strategic operational categories, enabling automatic
    # log categorization without manual wiring. Supports monitoring, debugging,
    # and compliance requirements by routing logs to appropriate operational
    # contexts.
    #
    # @return [String] The inferred category name ('App' if no pattern matches)
    #
    def infer_category
      class_name = self.class.name

      # Check for strategic category patterns in class name
      case class_name
      in /Authentication|Auth(?!or)/i
        'Auth'
      in /Familia/i
        'Familia'
      in /HTTP|Request|Response|Controller/i
        'HTTP'
      in /Otto/i
        'Otto'
      in /Rhales/i
        'Rhales'
      in /Secret|Metadata/i
        'Secret'
      in /Sequel/i
        'Sequel'
      in /Session/i
        'Session'
      else
        'App' # default fallback
      end
    end
  end
end
