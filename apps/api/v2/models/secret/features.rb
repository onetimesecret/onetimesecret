# apps/api/v2/models/secret/features.rb

Dir.glob(File.join(File.dirname(__FILE__), 'features', '*.rb')).each do |file|
  require file
end
