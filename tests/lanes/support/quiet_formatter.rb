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
# Loaded through SPEC_OPTS (`--require <this file> --format
# Lanes::QuietFormatter`), which tests/lanes/run sets below its env scrub
# and only under --quiet, so CI logs and default runs never see it.
module Lanes
  class QuietFormatter < RSpec::Core::Formatters::BaseTextFormatter
    RSpec::Core::Formatters.register self
  end
end
