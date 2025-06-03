base_path = File.expand_path File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(base_path, 'lib')

require 'onetime'
require 'onetime/migration'

# Convert symbol keys to strings
# perl -pe 's/^(\s*):(\w+)/$1$2/g' etc/config.example.yaml > etc/config.example.converted.yaml
