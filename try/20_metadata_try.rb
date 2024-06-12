# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot!

## Keys are consistent for Metadata
@metadata = Onetime::Metadata.new :metadata, :entropy
[@metadata.rediskey, @metadata.db, @metadata.secret_key, @metadata.all]
#=> ['metadata:ivfn09cpriklqii1zagw6fc96suh8bp:object', 7, nil, {}]

## Keys don't change with values
@metadata.secret_key = :hihi
[@metadata.rediskey, @metadata.secret_key, @metadata.all]
#=> ['metadata:ivfn09cpriklqii1zagw6fc96suh8bp:object', :hihi, {"secret_key"=>"hihi"}]

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
