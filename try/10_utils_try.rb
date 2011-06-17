require 'ots'

## Create a strand
OTS::Utils.strand.class
#=> String

## strand is 12 chars by default
OTS::Utils.strand.size
#=> 12

## strand can be n chars
OTS::Utils.strand(20).size
#=> 20
