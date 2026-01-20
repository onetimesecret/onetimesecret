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
