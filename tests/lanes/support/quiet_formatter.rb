# tests/lanes/support/quiet_formatter.rb
#
# frozen_string_literal: true

require 'rspec/core/formatters/base_text_formatter'

# The rspec formatter behind `tests/lanes/run <lane> --quiet`: failures,
# pending examples, the summary line and the seed, and nothing per passing
# example. No built-in formatter has that shape — `progress` still prints a
# dot per example (thousands on a full lane) and `failures` prints one
# location per failure with neither the diff nor the summary.
#
# BaseTextFormatter registers exactly the notifications wanted here
# (message, dump_failures, dump_summary, dump_pending, seed); the per-example
# ones (example_passed/failed/pending) live only in its subclasses. Registering
# this class with no notifications of its own keeps the inherited set — the
# loader collects notifications along the ancestor chain — so the whole
# formatter is the inheritance.
#
# Loaded by `--require <this file> --format Lanes::QuietFormatter` on the
# rspec command line, which tests/lanes/support/rspec_format.rb adds when
# LANES_RSPEC_CONSOLE=quiet (tests/lanes/run --quiet) and leaves out
# otherwise, so a default run never sees it. It replaces the console
# formatter only: the JSON formatter a run with RSPEC_OUTPUT_FILE has is
# passed beside it.
module Lanes
  class QuietFormatter < RSpec::Core::Formatters::BaseTextFormatter
    RSpec::Core::Formatters.register self
  end
end
