# tests/helpers/test_logic.rb

require_relative 'test_models'

require 'onetime/logic'

Logic = TestVersion::Logic

# Initialize rate limit events based on configuration. This
# mimics the behaviour of apps/api/v*/application.rb.
#
# NOTE: This is disabled b/c it causes 24_logic_destroy_account to
# fail but this test_logic helper is used by multiple tryouts so
# leaving this note here in case having it disabled causes
# other tryouts to fail.
#
# RateLimit.register_events({destroy_account: 1}, freeze: false)
