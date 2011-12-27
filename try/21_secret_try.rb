require 'onetime'


## Can create Secret
s = Onetime::Secret.new :private
s.class
#=> Onetime::Secret

## Keys are consistent for Metadata
s = Onetime::Metadata.new :metadata, :entropy
s.rediskey
#=> 'metadata:8o719hhgf2t8eh15bdabkm6n98pmd97:object'

## Keys are consistent for Secrets
s = Onetime::Secret.new :shared, :entropy
p s.name
s.rediskey
#=> 'secret:ct2cju1cwhqxcbh8de89sezrw0mtusa:object'

## But can be modified with entropy
s = Onetime::Secret.new :shared, [:some, :fixed, :values]
s.rediskey
#=> 'secret:ntit96jrq77myf5z0a333uvld21o6wq:object'

## Generate a pair
@metadata, @secret = Onetime::Secret.spawn_pair :anon, :tryouts
[@metadata.nil?, @secret.nil?]
#=> [false, false]

## Private keys match
!@secret.metadata_key.nil? && @secret.metadata_key == @metadata.key
#=> true

## Shared keys match
!@metadata.secret_key.nil? && @metadata.secret_key == @secret.key
#=> true

## Kinds are correct
[@metadata.class, @secret.class]
#=> [OT::Metadata, OT::Secret]

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
metadata, secret = Onetime::Secret.spawn_pair :anon, :tryouts
metadata.viewed!
[metadata.viewed, metadata.state]
#=> [Time.now.utc.to_i.to_s, 'viewed']

## Can set shared secret to viewed state
metadata, secret = Onetime::Secret.spawn_pair :anon, :tryouts
metadata.save && secret.save
secret.viewed!
metadata = secret.load_metadata
# NOTE: The secret no longer keeps a reference to the metadata
[metadata.shared, metadata.state, secret.viewed, secret.state]
##=> [Time.now.utc.to_i.to_s, 'shared', Time.now.utc.to_i.to_s, 'viewed']
