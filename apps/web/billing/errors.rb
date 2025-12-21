# apps/web/billing/errors.rb
#
# frozen_string_literal: true

module Billing
  # General billing operations problem - inherits from Onetime::Problem
  # for consistency with the application's error hierarchy.
  class OpsProblem < Onetime::Problem
  end

  # Raised when an operation is explicitly forbidden by business rules.
  # For example, attempting to update an existing Stripe price (which
  # is immutable in Stripe's API design).
  #
  # Uses a custom exit code (87) to distinguish from general errors
  # when running CLI commands.
  class ForbiddenOperation < RuntimeError
    EXIT_CODE = 87

    attr_reader :message

    def initialize(message = 'Operation forbidden')
      super
      @message = message
    end

    def exit_code
      EXIT_CODE
    end
  end
end
