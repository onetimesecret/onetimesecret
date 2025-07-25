# apps/api/v2/models.rb

# Load the model accessories before the models that use them.
require_relative 'models/features'
require_relative 'models/mixins'

# Load the models
require_relative 'models/mutable_config'
require_relative 'models/metadata'
require_relative 'models/secret'
require_relative 'models/session'
require_relative 'models/customer'
require_relative 'models/custom_domain'
require_relative 'models/feedback'
