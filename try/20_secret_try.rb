require 'onetime'


## Can create Secret
s = Onetime::Secret.new :private
s.class
#=> Onetime::Secret

## Secret.rediskey
Onetime::Secret.rediskey :poop
#=> 'onetime:secret:poop:object'

## Keys are consistent for :private
s = Onetime::Secret.new :private
s.rediskey
#=> 'onetime:secret:sv79fy0gw2uliz9p27w78m28n9jl1gm:object'

## Keys are consistent for :shared
s = Onetime::Secret.new :shared
s.rediskey
#=> 'onetime:secret:mrx810potfbxsf8bds8lwijmkzmb4si:object'

## But can be modified with entropy
s = Onetime::Secret.new :shared, [:some, :fixed, :values]
s.rediskey
#=> 'onetime:secret:toi8vxju6wn1yjldji4zax43f1s3ki7:object'

## Generate a pair
@psecret, @ssecret = Onetime::Secret.generate_pair :tryouts
[@psecret.nil?, @ssecret.nil?]
#=> [false, false]

## Private keys match
!@ssecret.paired_key.nil? && @ssecret.paired_key == @psecret.key
#=> true

## Shared keys match
!@psecret.paired_key.nil? && @psecret.paired_key == @ssecret.key
#=> true

## Kinds are correct
[@psecret.kind, @ssecret.kind]
#=> [:private, :shared]

