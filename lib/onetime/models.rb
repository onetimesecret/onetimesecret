# lib/onetime/models.rb
#
# frozen_string_literal: true

require_relative 'models/features'
require_relative 'models/secret'
require_relative 'models/organization'
require_relative 'models/organization_membership'
require_relative 'models/customer'
require_relative 'models/custom_domain'
# Receipt must be loaded AFTER Organization and CustomDomain because
# Receipt.participates_in declarations reference those classes
require_relative 'models/receipt'
require_relative 'models/feedback'
require_relative 'models/custom_domain/sso_config'
require_relative 'models/custom_domain/mailer_config'
require_relative 'models/custom_domain/incoming_config'

# Housekeeping chores - loaded after models so chore DSL is available.
# Ruby 3+ Dir.glob returns results in deterministic (sorted) order.
Dir.glob(File.join(__dir__, 'models', '*', 'chores', '*.rb')).each do |chore_file|
  require chore_file
end
