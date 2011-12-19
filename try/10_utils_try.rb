require 'onetime'

## Create a strand
Onetime::Utils.strand.class
#=> String

## strand is 12 chars by default
Onetime::Utils.strand.size
#=> 12

## strand can be n chars
Onetime::Utils.strand(20).size
#=> 20

## Obscure email address (6 or more chars)
Onetime::Utils.obscure_email('tryouts@onetimesecret.com')
#=> 't*****s@onetimesecret.com'

## Obscure email address (4 or more chars)
Onetime::Utils.obscure_email('dave@onetimesecret.com')
#=> 'd******@onetimesecret.com'

## Obscure email address (less than 4 chars)
Onetime::Utils.obscure_email('dm@onetimesecret.com')
#=> '*******@onetimesecret.com'
