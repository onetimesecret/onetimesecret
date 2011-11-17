require 'onetime'

# sudo mkdir /etc/onetime
# mkdir ~/.onetime
# sudo touch /etc/onetime/config
# touch ~/.onetime/config

## Available config paths in default mode (app)
Onetime::Config.find_configs
#=> ["/etc/onetime/config", "/Users/delano/Projects/private/onetimesecret.com/etc/config"]

## Available config paths in cli mode
OT.mode = :cli
Onetime::Config.find_configs
#=> ["/Users/delano/.onetime/config", "/etc/onetime/config", "/Users/delano/Projects/private/onetimesecret.com/etc/config"]

## Available config paths in app mode
OT.mode = :app
Onetime::Config.find_configs
#=> ["/etc/onetime/config", "/Users/delano/Projects/private/onetimesecret.com/etc/config"]

## Finds a config path
Onetime::Config.path
#=> "/etc/onetime/config"

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

