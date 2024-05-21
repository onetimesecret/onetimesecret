# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.example')
OT.load! :cli

# sudo mkdir /etc/onetime
# mkdir ~/.onetime
# sudo touch /etc/onetime/config
# touch ~/.onetime/config

## Available config paths in default mode (app)
Onetime::Config.find_configs
#=> ["/etc/onetime/config", File.join(OT::HOME, "etc/config")]

## Available config paths in cli mode
OT.mode = :cli
Onetime::Config.find_configs
#=> [File.join(OT.sysinfo.home, ".onetime/config"), "/etc/onetime/config", File.join(OT::HOME, "etc/config")]

## Available config paths in app mode
OT.mode = :app
Onetime::Config.find_configs
#=> ["/etc/onetime/config", File.join(OT::HOME, "etc/config")]

## Finds a config path
relative_path = Onetime::Config.path.gsub("#{__dir__}/", '')
relative_path
#=> "../etc/config.example"

## Can load config
@config = Onetime::Config.load
@config.class
#=> Hash

## Has basic config
[@config[:site].class, @config[:redis].class]
#=> [Hash, Hash]

## OT.load!
OT.load! :tryouts
[OT.mode, OT.conf.class]
#=> [:tryouts, Hash]
