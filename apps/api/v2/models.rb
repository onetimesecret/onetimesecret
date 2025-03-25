# apps/api/v2/models.rb

require 'v1/models/mixins' # v2 uses the v1 mixins

require_relative 'models/metadata'
require_relative 'models/secret'
require_relative 'models/session'
require_relative 'models/customer'
require_relative 'models/email_receipt'
require_relative 'models/custom_domain'
require_relative 'models/feedback'
require_relative 'models/exception_info'
require_relative 'models/rate_limit'
