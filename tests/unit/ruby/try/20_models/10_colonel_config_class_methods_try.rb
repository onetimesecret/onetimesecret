# tests/unit/ruby/try/20_models/10_colonel_config_class_methods_try.rb

# redis-server --port 2121 --save "" --appendonly no
# clear && ONETIME_DEBUG=1 REDIS_URL='redis://127.0.0.1:2121/0' bundle exec try -vf tests/unit/ruby/try/20_models/10_colonel_config_class_methods_try.rb
# REDIS_URL='redis://127.0.0.1:2121/0' ruby support/clear_redis.rb --all --force

# Testing race condition with sorted sets using low precision now:
# while true; do pnpm run redis:clean --force && pnpm run test:tryouts tests/unit/ruby/try/20_models/10_colonel_config_class_methods_try.rb || break; done

require 'securerandom'
require 'fakeredis'

require_relative '../test_models'

#Familia.debug = true

# Familia.redis = Redis.new

# Load the app
OT.boot! :test, true

# Clear any existing colonel configs to start fresh
V2::ColonelConfig.values.clear
V2::ColonelConfig.stack.clear

@test_config = {
  site: {
    interface: {
      host: 'localhost',
      port: 3000,
      ssl: false
    },
    secret_options: {
      max_size: 1024,
      default_ttl: 3600
    }
  },
  mail: {
    from: 'noreply@example.com',
    smtp: {
      host: 'smtp.example.com',
      port: 587
    }
  },
  limits: {
    create_secret: 250,
    send_feedback: 10
  },
  experimental: {
    enabled: false
  },
  diagnostics: {
    enabled: true,
    level: 'info'
  }
}

@colonel_config_hash = {
  interface: {
    host: 'custom.example.com',
    port: 8080,
    ssl: true
  },
  secret_options: {
    max_size: 2048
  },
  mail: {
    from: 'custom@example.com'
  },
  limits: {
    create_secret: 500
  },
  experimental: {
    enabled: true
  },
  diagnostics: {
    level: 'debug'
  }
}

@email = "tryouts+colonel+#{Time.now.to_i}@onetimesecret.com"
@customer = V1::Customer.create @email

@obj_config_data = {
  interface: { host: 'create.example.com', port: 9000 },
  mail: { from: 'create@example.com' },
  custid: @customer.custid,
  comment: 'Test config creation'
}

## Can extract colonel sections from full config using FIELD_MAPPINGS
V2::ColonelConfig.extract_colonel_config(@test_config)
#=> {:interface=>{:host=>"localhost", :port=>3000, :ssl=>false}, :secret_options=>{:max_size=>1024, :default_ttl=>3600}, :mail=>{:from=>"noreply@example.com", :smtp=>{:host=>"smtp.example.com", :port=>587}}, :limits=>{:create_secret=>250, :send_feedback=>10}, :experimental=>{:enabled=>false}, :diagnostics=>{:enabled=>true, :level=>"info"}}

## Can construct onetime config structure from colonel config hash
V2::ColonelConfig.construct_onetime_config(@colonel_config_hash)
#=> {:site=>{:interface=>{:host=>"custom.example.com", :port=>8080, :ssl=>true}, :secret_options=>{:max_size=>2048}}, :mail=>{:from=>"custom@example.com"}, :limits=>{:create_secret=>500}, :experimental=>{:enabled=>true}, :diagnostics=>{:level=>"debug"}}

## Can construct onetime config from partial colonel config hash
partial_config = { interface: { host: 'partial.example.com' }, mail: { from: 'partial@example.com' } }
V2::ColonelConfig.construct_onetime_config(partial_config)
#=> {:site=>{:interface=>{:host=>"partial.example.com"}}, :mail=>{:from=>"partial@example.com"}}

## Can handle empty colonel config hash
V2::ColonelConfig.construct_onetime_config({})
#=> {}

## Can handle nil values in colonel config
nil_config = { interface: { host: nil }, mail: nil }
result = V2::ColonelConfig.construct_onetime_config(nil_config)
result.has_key?(:mail)
#=> false

## Can create a new colonel config record
@obj = V2::ColonelConfig.create(**@obj_config_data)
@obj.class
#=> V2::ColonelConfig

## Created colonel config has proper identifier
@obj.identifier.length
#=> 31

## Created colonel config exists in Redis
V2::ColonelConfig.exists?(@obj.identifier)
#=> true

## Cannot create duplicate colonel config with same identifier
begin
  duplicate = V2::ColonelConfig.new
  duplicate.instance_variable_set(:@configid, @obj.identifier)
  duplicate.save
rescue OT::Problem => e
  e.message.include?("Cannot clobber V2::ColonelConfig")
end
#=> true

## Can check if customer owns a colonel config
p [:owner, @obj.owner, @customer.custid]
@obj.owner?(@customer)
#=> true

## Can check ownership with customer ID string
@obj.owner?(@customer.custid)
#=> true

## Different customer does not own the config
other_email = "tryouts+other+#{Time.now.to_i}@onetimesecret.com"
@other_customer = V1::Customer.create(other_email)
@obj.owner?(@other_customer)
#=> false

## Can add colonel config to tracking sets
V2::ColonelConfig.add(@obj)
V2::ColonelConfig.values.member?(@obj.identifier)
#=> true

## Can retrieve all colonel configs
all_configs = V2::ColonelConfig.all
all_configs.any? { |c| c.identifier == @obj.identifier }
#=> true

## Can get current colonel config from stack
V2::ColonelConfig.current.identifier
#=> @obj.identifier

## Can create second colonel config and it becomes current
@obj_config_data2 = {
  interface: { host: 'second.example.com', port: 8000 },
  mail: { from: 'second@example.com' },
  custid: @customer.custid,
  comment: 'Second test config'
}
@obj2 = V2::ColonelConfig.create(**@obj_config_data2)
p [@obj2.identifier, V2::ColonelConfig.current.identifier]
V2::ColonelConfig.current.identifier
#=> @obj2.identifier

## Can get previous colonel config from stack
V2::ColonelConfig.previous.identifier
#=> @obj.identifier

## Can retrieve recent colonel configs within time window
recent_configs = V2::ColonelConfig.recent(1.hour)
recent_configs.length >= 2
#=> true

## Can remove colonel config from values set
V2::ColonelConfig.rem(@obj2)
V2::ColonelConfig.values.member?(@obj2.identifier)
#=> false

## Removed config still exists in Redis but not in values set
@obj2.exists?
#=> true

## Can remove bad config from both values and stack
p [:working_on, @obj2.identifier]
p [:before, V2::ColonelConfig.stack.all]
V2::ColonelConfig.remove_bad_config(@obj2)
p [:after, V2::ColonelConfig.stack.all]
V2::ColonelConfig.stack.member?(@obj2.identifier)
#=> false

## Extract colonel sections handles missing nested keys gracefully
incomplete_config = { site: { interface: { host: 'test' } } }
result = V2::ColonelConfig.extract_colonel_config(incomplete_config)
result[:secret_options]
#=> nil

## Extract colonel sections handles completely missing sections
minimal_config = { other_section: { value: 'test' } }
result = V2::ColonelConfig.extract_colonel_config(minimal_config)
[result[:interface], result[:mail], result[:limits]]
#=> [nil, nil, nil]

## Construct onetime config skips nil values appropriately
config_with_nils = { interface: nil, mail: { from: 'test@example.com' } }
result = V2::ColonelConfig.construct_onetime_config(config_with_nils)
p [:plop, result]
[result.has_key?(:site), result.dig(:site, :interface).nil?]
#=> [false, true]

## FIELD_MAPPINGS constant is properly defined
V2::ColonelConfig::FIELD_MAPPINGS.keys.sort
#=> [:diagnostics, :experimental, :interface, :limits, :mail, :secret_options]

## FIELD_MAPPINGS has correct paths for nested site sections
[
  V2::ColonelConfig::FIELD_MAPPINGS[:interface],
  V2::ColonelConfig::FIELD_MAPPINGS[:secret_options]
]
#=> [[:site, :interface], [:site, :secret_options]]

## FIELD_MAPPINGS has correct paths for top-level sections
[
  V2::ColonelConfig::FIELD_MAPPINGS[:mail],
  V2::ColonelConfig::FIELD_MAPPINGS[:limits]
]
#=> [[:mail], [:limits]]

# Cleanup
@customer.destroy!
@other_customer.destroy!
