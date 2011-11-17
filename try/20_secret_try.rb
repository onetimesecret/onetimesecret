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
@metadata, @secret = Onetime::Secret.generate_pair :tryouts
[@metadata.nil?, @secret.nil?]
#=> [false, false]

## Private keys match
!@secret.paired_key.nil? && @secret.paired_key == @metadata.key
#=> true

## Shared keys match
!@metadata.paired_key.nil? && @metadata.paired_key == @secret.key
#=> true

## Kinds are correct
[@metadata.kind, @secret.kind]
#=> [:private, :shared]

## Can save a secret
@metadata.save
#=> true

## A saved secret exists
@metadata.exists?
#=> true

## A secret can be destroyed
@metadata.destroy!
#=> 1

## Can set private secret to viewed state
metadata, secret = Onetime::Secret.generate_pair :tryouts
metadata.viewed!
[metadata.viewed, metadata.state]
#=> [Time.now.utc.to_i, 'viewed']

## Can set shared secret to viewed state
metadata, secret = Onetime::Secret.generate_pair :tryouts
metadata.save && secret.save
secret.viewed!
metadata = secret.load_metadata
[metadata.shared, metadata.state, secret.viewed, secret.state]
#=> [Time.now.utc.to_i, 'shared', Time.now.utc.to_i, 'viewed']
