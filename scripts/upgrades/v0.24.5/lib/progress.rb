# frozen_string_literal: true

module Upgrade
  # Lightweight progress reporter for long-running upgrade loops.
  #
  # On a TTY, redraws a single line via \r every N ticks so 400k+ iterations
  # don't flood the terminal. Off TTY (logs, CI), emits a milestone line
  # every 10*N ticks instead so output stays bounded but progress is still
  # observable in piped/redirected output.
  #
  # Usage:
  #   reporter = Upgrade::ProgressReporter.new('customers')
  #   File.foreach(path) do |line|
  #     reporter.tick
  #     # ...
  #   end
  #   reporter.finish
  class ProgressReporter
    DEFAULT_EVERY = 1000
    LINE_WIDTH    = 72

    def initialize(label, every: DEFAULT_EVERY, io: $stdout)
      @label           = label
      @every           = [every.to_i, 1].max
      @io              = io
      @tty             = io.respond_to?(:tty?) && io.tty?
      @count           = 0
      @started         = Time.now
      @done            = false
      @next_threshold  = @every
    end

    # `by > 1` is supported: the threshold logic crosses any number of
    # multiples in one call without skipping a redraw.
    def tick(by = 1)
      @count += by
      return if @count < @next_threshold

      write_status
      @next_threshold = ((@count / @every) + 1) * @every
    end

    def finish
      return if @done

      write_status(force: true)
      @io.puts if @tty
      @io.flush
      @done = true
    end

    attr_reader :count

    private

    def write_status(force: false)
      if @tty
        @io.print "\r#{format_message.ljust(LINE_WIDTH)}"
        @io.flush
      elsif force || (@count % (@every * 10)).zero?
        @io.puts format_message
        @io.flush
      end
    end

    def format_message
      elapsed = (Time.now - @started).to_f
      rate    = elapsed > 0 ? (@count / elapsed).round : 0
      "    #{@label}: #{@count.to_s.rjust(9)} (#{rate}/s)"
    end
  end
end
