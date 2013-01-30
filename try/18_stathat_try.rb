require 'onetime'

OT.load! :cli


## Has API key
Onetime.conf[:stathat][:apikey].to_s.empty?
#=> false

## Is enabled
Onetime.conf[:stathat][:enabled]
#=> true

## Can post count
apikey = Onetime.conf[:stathat][:apikey]
StatHat::API.ez_post_count("OTS TEST 1 (count)", apikey, 1)
#=> true

## Can post value
apikey = Onetime.conf[:stathat][:apikey]
StatHat::API.ez_post_value("OTS TEST 1 (value)", apikey, rand*1000)
#=> true

## Logic has apikey
OT::Logic.stathat_apikey.to_s.empty?
#=> false

## StatHat is enabled
OT::Logic.stathat_enabled
#=> true

## Logic can set a count
OT::Logic.stathat_count("OTS TEST 2 (count)", 1)
#=> true

## Logic can set a value
OT::Logic.stathat_value("OTS TEST 2 (value)", rand*1000)
#=> true

## StatHat can be disabled
OT::Logic.stathat_enabled = false
#=> false

## StatHat can be disabled
OT::Logic.stathat_enabled
#=> false

## Logic won't set a count when disabled
OT::Logic.stathat_count("OTS TEST 3 (count)", 1)
#=> false

## Logic won't set a value when disabled
OT::Logic.stathat_value("OTS TEST 3 (value)", rand*1000)
#=> false


