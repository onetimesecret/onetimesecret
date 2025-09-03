# apps/api/v2/models.rb

# Load all of our model features before the models so that
# they're accessible
features_dir = File.join(__dir__, 'models', 'features')
OT.ld "[DEBUG] Loading features from #{features_dir}"
if Dir.exist?(features_dir)
  Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
    OT.ld "[DEBUG] Loading feature #{feature_file}"
    require_relative feature_file
  end
end

require_relative 'models/mixins'
require_relative 'models/metadata'
require_relative 'models/secret'
require_relative 'models/session'
require_relative 'models/customer'
require_relative 'models/custom_domain'
require_relative 'models/team'
require_relative 'models/organization'
require_relative 'models/feedback'
