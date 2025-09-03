# apps/api/v2/models/customer/features.rb

# Load all of our model features before the models so that
# they're accessible
features_dir = File.join(__dir__, 'features')
OT.ld "[DEBUG] Loading features from #{features_dir}"
if Dir.exist?(features_dir)
  Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
    OT.ld "[DEBUG] Loading feature #{feature_file}"
    require_relative feature_file
  end
end
