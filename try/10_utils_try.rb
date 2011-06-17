require 'onetime'

## Create a strand
OneTime::Utils.strand.class
#=> String

## strand is 12 chars by default
OneTime::Utils.strand.size
#=> 12

## strand can be n chars
OneTime::Utils.strand(20).size
#=> 20
