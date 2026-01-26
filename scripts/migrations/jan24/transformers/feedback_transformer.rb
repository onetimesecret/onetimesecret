# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Passes through feedback key unchanged.
  class FeedbackTransformer < BaseTransformer
    def default_stats
      { scanned: 0, passed_through: 0 }
    end

    def route(record, key)
      case key
      when /^feedback$/
        # Pass through feedback as-is
        @stats[:scanned]        += 1
        @stats[:passed_through] += 1
        record
      else
        skip_other_key
      end
    end
  end
end
