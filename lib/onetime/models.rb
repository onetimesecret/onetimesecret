# lib/onetime/models.rb

require_relative 'models/features'
require_relative 'models/metadata'
require_relative 'models/secret'
require_relative 'models/organization'
require_relative 'models/customer'
require_relative 'models/team'  # Must load after Customer (participates_in dependency)
require_relative 'models/custom_domain'
require_relative 'models/feedback'
