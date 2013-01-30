require 'onetime'

OT.load! :cli

## Clear values
OT::Entropy.values.clear
#=> 1

## Knows the count
OT::Entropy.count
#=> 0

## Can pop a value even when empty
val = OT::Entropy.pop
[val.size, val.class]
#=> [12, String]

## Can generate values
OT::Entropy.generate 10
#=> 10

## Still knows the count
OT::Entropy.count
#=> 10

## Can pop a value even when empty
val = OT::Entropy.pop
[val.size, val.class]
#=> [12, String]

## Still knows the count
OT::Entropy.count
#=> 9
