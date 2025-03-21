# apps/api/v1/models.rb

require_relative 'models/mixins'
require_relative 'models/metadata'
require_relative 'models/secret'
require_relative 'models/session'
require_relative 'models/customer'
require_relative 'models/splittest'
require_relative 'models/email_receipt'
require_relative 'models/custom_domain'
require_relative 'models/feedback'
require_relative 'models/exception_info'
require_relative 'models/rate_limit'

# For backwards compatibility with v0.18.3 and earlier, these redis database
# IDs had been hardcoded in their respective model classes which we maintain
# here for existing installs. If they haven't had a chance to update their
# etc/config.yaml files OR
#
# For installs running via docker image + environment vars, this change should
# be a non-issue as long as the default config (etc/config.example.yaml) is
# used (which it is in the official images).
#
DATABASE_IDS = {
  session: 1,
  splittest: 1,
  ratelimit: 2,
  custom_domain: 6,
  customer: 6,
  subdomain: 6,
  metadata: 7,
  email_receipt: 8,
  secret: 8,
  feedback: 11,
  exceptions: 12,
}
