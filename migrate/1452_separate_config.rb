base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'

# Order of Operations
#
# 1) Create backup of source config file (use dated suffix)
# cp etc/config.example.yaml etc/config.example.yaml.`date +%Y%m%d%H%M%S`
#
# 2) Convert symbol keys to strings
# perl -pe 's/^(\s*):(\w+)/$1$2/g' etc/config.example.yaml > etc/config.converted.yaml
#
# 3) Separate config into separate files
# ./support/generate-config-from-mapping.rb
#
# 4) Move the static config to original source file path
# mv etc/config.static.yaml etc/config.yaml
#
# 5) Move the dynamic config to a place where V2::SystemSettings can find it
# mv etc/config.dynamic.yaml apps/api/v2/models/system_settings.defaults.yaml
