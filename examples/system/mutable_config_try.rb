# ./tryouts/models/mutable_config_class_methods_try.rb

# redis-server --port 2121 --save "" --appendonly no
# clear && ONETIME_DEBUG=1 REDIS_URL='redis://127.0.0.1:2121/0' bundle exec try -vf tests/unit/ruby/try/20_models/10_mutable_config_class_methods_try.rb
# REDIS_URL='redis://127.0.0.1:2121/0' ruby support/clear_redis.rb --all --force

# Testing race condition with sorted sets using low precision now:
# while true; do pnpm run redis:clean --force && pnpm run test:tryouts tests/unit/ruby/try/20_models/10_mutable_config_class_methods_try.rb || break; done

require 'securerandom'
require 'fakeredis'

require_relative '../../tests/helpers/test_models'

#Familia.debug = true

# Familia.redis = Redis.new

# Load the app
OT.boot! :test, true

# Clear any existing mutable config to start fresh
V2::MutableConfig.values.clear
V2::MutableConfig.stack.clear

@test_config = {
  site: {
    host: 'localhost',
    port: 3000,
    ssl: false,
    interface: {
      ui: {
        enabled: true,
      },
      api: {
        enabled: true
      }
    },
    authentication: {
      signup: {
        enabled: true
      },
      signin: {
        enabled: true
      }
    },
    secret_options: {
      max_size: 1024,
      default_ttl: 3600
    }
  },
  mail: {
    from: 'noreply@example.com',
    truemail: {
      validation: true
    },
    smtp: {
      host: 'smtp.example.com',
      port: 587
    }
  },
  limits: {
    create_secret: 250,
    send_feedback: 10
  }
}

@mutable_config_hash = {
  ui: {
    enabled: true,
    signup: {
      enabled: false
    },
    signin: {
      enabled: true
    }
  },
  api: {
    enabled: true
  },
  secret_options: {
    anonymous: {
      max_size: 1024
    },
    standard: {
      max_size: 2048
    },
    enhanced: {
      max_size: 4096
    }
  },
  mail: {
    validation: {
      recipients: true,
      accounts: true
    }
  },
  limits: {
    create_secret: 500
  }
}

@email = "tryouts+colonel+#{Time.now.to_i}@onetimesecret.com"
@customer = V1::Customer.create @email

@obj_config_data = {
  ui: { enabled: true },
  api: { enabled: true },
  mail: { validation: { recipients: true } },
  custid: @customer.custid,
  comment: 'Test config creation'
}

## Can extract settings sections from full config using FIELD_MAPPINGS
V2::MutableConfig.extract_mutable_config(@test_config)
#=> {:ui=>{:enabled=>true}, :secret_options=>{:max_size=>1024, :default_ttl=>3600}, :mail=>{:from=>"noreply@example.com", :truemail=>{:validation=>true}, :smtp=>{:host=>"smtp.example.com", :port=>587}}, :limits=>{:create_secret=>250, :send_feedback=>10}, :api=>{:enabled=>true}}

## Can construct onetime config structure from mutable config hash
V2::MutableConfig.construct_onetime_config(@mutable_config_hash)
#=> {:site=>{:interface=>{:ui=>{:enabled=>true, :signup=>{:enabled=>false}, :signin=>{:enabled=>true}}, :api=>{:enabled=>true}}, :secret_options=>{:anonymous=>{:max_size=>1024}, :standard=>{:max_size=>2048}, :enhanced=>{:max_size=>4096}}}, :mail=>{:validation=>{:recipients=>true, :accounts=>true}}, :limits=>{:create_secret=>500}}

## Can construct onetime config from partial mutable config hash
partial_config = { ui: { enabled: false }, mail: { validation: { recipients: false } } }
V2::MutableConfig.construct_onetime_config(partial_config)
#=> {:site=>{:interface=>{:ui=>{:enabled=>false}}}, :mail=>{:validation=>{:recipients=>false}}}

## Can handle empty mutable config hash
V2::MutableConfig.construct_onetime_config({})
#=> {}

## Can handle nil values in mutable config
nil_config = { ui: { enabled: nil }, mail: nil }
result = V2::MutableConfig.construct_onetime_config(nil_config)
result.has_key?(:mail)
#=> false

## Can create a new mutable config record
@obj = V2::MutableConfig.create(**@obj_config_data)
@obj.class
#=> V2::MutableConfig

## Created mutable config has proper identifier
@obj.identifier.length
#=> 31

## Created mutable config exists in Redis
V2::MutableConfig.exists?(@obj.identifier)
#=> true

## Cannot create duplicate mutable config with same identifier
begin
  duplicate = V2::MutableConfig.new
  duplicate.instance_variable_set(:@configid, @obj.identifier)
  duplicate.save
rescue OT::Problem => e
  e.message.include?("Cannot clobber V2::MutableConfig")
end
#=> true

## Can check if customer owns a mutable config
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

## Can add mutable config to tracking sets
V2::MutableConfig.add(@obj)
V2::MutableConfig.values.member?(@obj.identifier)
#=> true

## Can retrieve all mutable config
all_configs = V2::MutableConfig.all
all_configs.any? { |c| c.identifier == @obj.identifier }
#=> true

## Can get current mutable config from stack
V2::MutableConfig.current.identifier
#=> @obj.identifier

## Can create second mutable config and it becomes current
@obj_config_data2 = {
  ui: { enabled: false },
  api: { enabled: false },
  mail: { validation: { accounts: false } },
  custid: @customer.custid,
  comment: 'Second test config'
}
@obj2 = V2::MutableConfig.create(**@obj_config_data2)
p [@obj2.identifier, V2::MutableConfig.current.identifier]
V2::MutableConfig.current.identifier
#=> @obj2.identifier

## Can get previous mutable config from stack
V2::MutableConfig.previous.identifier
#=> @obj.identifier

## Can retrieve recent mutable config within time window
recent_configs = V2::MutableConfig.recent(1.hour)
recent_configs.length >= 2
#=> true

## Can remove mutable config from values set
V2::MutableConfig.rem(@obj2)
V2::MutableConfig.values.member?(@obj2.identifier)
#=> false

## Removed config still exists in Redis but not in values set
@obj2.exists?
#=> true

## Can remove bad config from both values and stack
p [:working_on, @obj2.identifier]
p [:before, V2::MutableConfig.stack.all]
V2::MutableConfig.remove_bad_config(@obj2)
p [:after, V2::MutableConfig.stack.all]
V2::MutableConfig.stack.member?(@obj2.identifier)
#=> false

## Extract settings sections handles missing nested keys gracefully
incomplete_config = { site: { interface: { ui: { enabled: true } } } }
result = V2::MutableConfig.extract_mutable_config(incomplete_config)
result[:secret_options]
#=> nil

## Extract settings sections handles completely missing sections
minimal_config = { other_section: { value: 'test' } }
result = V2::MutableConfig.extract_mutable_config(minimal_config)
[result[:ui], result[:mail], result[:limits]]
#=> [nil, nil, nil]

## Construct onetime config skips nil values appropriately
config_with_nils = { ui: nil, mail: { validation: { recipients: true } } }
result = V2::MutableConfig.construct_onetime_config(config_with_nils)
p [:plop, result]
[result.has_key?(:site), result.dig(:site, :interface).nil?]
#=> [false, true]

## FIELD_MAPPINGS constant is properly defined
V2::MutableConfig::FIELD_MAPPINGS.keys.sort
#=> [:api, :limits, :mail, :secret_options, :ui]

## FIELD_MAPPINGS has correct paths for nested site sections
[
  V2::MutableConfig::FIELD_MAPPINGS[:ui],
  V2::MutableConfig::FIELD_MAPPINGS[:secret_options]
]
#=> [[:site, :interface, :ui], [:site, :secret_options]]

## FIELD_MAPPINGS has correct paths for top-level sections
[
  V2::MutableConfig::FIELD_MAPPINGS[:mail],
  V2::MutableConfig::FIELD_MAPPINGS[:limits]
]
#=> [[:mail], [:limits]]

# Cleanup
@customer.destroy!
@other_customer.destroy!
