# tests/unit/ruby/try/test_logic.rb

require_relative 'test_models'

require 'onetime/logic'

Logic = TestVersion::Logic

# Initialize rate limit events based on configuration. This
# mimics the behaviour of apps/api/v*/application.rb.
RateLimit.register_events({destroy_account: 1})
