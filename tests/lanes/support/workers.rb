# tests/lanes/support/workers.rb
#
# frozen_string_literal: true

module Lanes
  # What the lane runner tells a rake task about in-lane workers (#4551),
  # read from the environment in one place:
  #
  #   LANES_WORKERS            rspec processes per invocation, from a lane's
  #                            env file or `tests/lanes/run --workers N`.
  #                            Unset or empty is 1: the serial command.
  #   LANES_RSPEC_STATUS_FILE  the lane's example status file, beside which
  #                            the workers write theirs. Unset outside the
  #                            runner.
  #
  # Here rather than in lib/tasks/spec.rake because that file is copied into
  # the OCI image, and nothing in the image may read a lane runner variable
  # (spec/unit/lanes/image_log_defaults_guard_spec.rb); the rake file loads
  # this one, which stays outside the image.
  module Workers
    COUNT_ENV       = 'LANES_WORKERS'
    STATUS_FILE_ENV = 'LANES_RSPEC_STATUS_FILE'

    module_function

    # @return [Integer] rspec processes per invocation, 1 when unset
    # @raise [ArgumentError] for a value that is not a positive integer
    def count(env = ENV)
      value = env.fetch(COUNT_ENV, '').to_s.strip
      return 1 if value.empty?

      workers = Integer(value, exception: false)
      raise ArgumentError, "#{COUNT_ENV} must be a positive integer, not #{value.inspect}" unless workers&.positive?

      workers
    end

    # @return [String, nil] the lane's status file, nil when unset or empty
    def status_file(env = ENV)
      value = env.fetch(STATUS_FILE_ENV, '').to_s
      value.empty? ? nil : value
    end
  end
end
