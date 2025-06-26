# tests/unit/ruby/try/test_logic.rb

require_relative './test_models'

require 'onetime/logic'

Logic = TestVersion::Logic

# This section defines rate limits for various events per user
# per a rolling 20 minute period. Each key is an event name
# and the value is the max count allowed. Changes require
# restart of the app.
LIMITS = {
  'check_status': 10000,
  'create_secret': 100000,
  'create_account': 10,
  'update_account': 10,
  'email_recipient': 50,
  'send_feedback': 10,
  'authenticate_session': 50,
  'dashboard': 5000,
  'failed_passphrase': 15,
  'show_metadata': 2000,
  'show_secret': 2000,
  'burn_secret': 2000,
  'destroy_account': 2,
  'forgot_password_request': 20,
  'forgot_password_reset': 30,
  'add_domain': 30,
  'remove_domain': 30,
  'list_domains': 100,
  'get_domain': 100,
  'verify_domain': 100,
  'get_page': 1000,
  'report_exception': 50,
  'attempt_secret_access': 10,
  'generate_apitoken': 50,
  'update_branding': 5,
  'destroy_session': 5,
  'get_domain_brand': 1000,
  'get_domain_logo': 1000,
  'get_image': 1000,
  'remove_domain_logo': 20,
  'show_account': 100,
  'stripe_webhook': 25,
  'update_domain_brand': 5,
  'view_colonel': 100,
  'external_redirect': 100,
  'update_mutable_config': 50,
}

# Initialize rate limit events based on configuration. This
# mimics the behaviour of apps/api/v*/application.rb.
#
# NOTE: This is disabled b/c it causes 24_logic_destroy_account to
# fail but this test_logic helper is used by multiple tryouts so
# leaving this note here in case having it disabled causes
# other tryouts to fail.
#
# RateLimit.register_events({destroy_account: 1}, freeze: false)
