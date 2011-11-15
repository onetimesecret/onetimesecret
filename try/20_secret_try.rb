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
#=> 'onetime:secret:ql74nsxoz4fx8llfcwk8s9rdhsecw6e:object'

## Keys are consistent for :shared
s = Onetime::Secret.new :shared
s.rediskey
#=> 'onetime:secret:e08ai8m00fqjzq0mhf9qgahryul8a99:object'

## But can be modified with entropy
s = Onetime::Secret.new :shared, [:some, :fixed, :values]
s.rediskey
#=> 'onetime:secret:9qz0no2zjyy8p1irl4v9kn5talo4rim:object'

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

## Can save a secret
@psecret.save
#=> true

## A saved secret exists
@psecret.exists?
#=> true

## A secret can be destroyed
@psecret.destroy!
#=> 1

## Can set private secret to viewed state
psecret, ssecret = Onetime::Secret.generate_pair :tryouts
psecret.viewed!
[psecret.viewed, psecret.state]
#=> [Time.now.utc.to_i, 'viewed']

## Can set shared secret to viewed state
psecret, ssecret = Onetime::Secret.generate_pair :tryouts
psecret.save && ssecret.save
ssecret.viewed!
psecret = ssecret.load_pair
[psecret.shared, psecret.state, ssecret.viewed, ssecret.state]
#=> [Time.now.utc.to_i, 'shared', Time.now.utc.to_i, 'viewed']
