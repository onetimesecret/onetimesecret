require 'onetime'

## Keys are consistent for Metadata
@metadata = Onetime::Metadata.new :metadata, :entropy
[@metadata.rediskey, @metadata.db, @metadata.secret_key, @metadata.all]
#=> ['metadata:8o719hhgf2t8eh15bdabkm6n98pmd97:object', 7, nil, {}]

## Keys don't change with values
@metadata.secret_key = :hihi
[@metadata.rediskey, @metadata.secret_key, @metadata.all]
#=> ['metadata:8o719hhgf2t8eh15bdabkm6n98pmd97:object', :hihi, {"secret_key"=>"hihi"}]

## Doesn't exist yet
@metadata2 = Onetime::Metadata.new :metadata, [OT.instance, Time.now.to_f, OT.entropy]
@metadata2.exists?
#=> false

## Does exist
@metadata2.save
p @metadata2.all
@metadata2.exists?
#=> true


@metadata.destroy!
@metadata2.destroy!
