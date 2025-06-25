# tests/unit/ruby/try/20_models/10_mutable_settings_class_methods_try.rb

# redis-server --port 2121 --save "" --appendonly no
# clear && ONETIME_DEBUG=1 REDIS_URL='redis://127.0.0.1:2121/0' bundle exec try -vf tests/unit/ruby/try/20_models/10_mutable_settings_class_methods_try.rb
# REDIS_URL='redis://127.0.0.1:2121/0' ruby support/clear_redis.rb --all --force

# Testing race condition with sorted sets using low precision now:
# while true; do pnpm run redis:clean --force && pnpm run test:tryouts tests/unit/ruby/try/20_models/10_mutable_settings_class_methods_try.rb || break; done

require 'securerandom'
require 'fakeredis'

require_relative '../test_models'

#Familia.debug = true

# Familia.redis = Redis.new

# Load the app
OT.boot! :test, true

# Clear any existing mutable settings to start fresh
V2::MutableSettings.values.clear
V2::MutableSettings.stack.clear

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

@mutable_settings_hash = {
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
V2::MutableSettings.extract_mutable_settings(@test_config)
#=> {:ui=>{:enabled=>true}, :secret_options=>{:max_size=>1024, :default_ttl=>3600}, :mail=>{:from=>"noreply@example.com", :truemail=>{:validation=>true}, :smtp=>{:host=>"smtp.example.com", :port=>587}}, :limits=>{:create_secret=>250, :send_feedback=>10}, :api=>{:enabled=>true}}

## Can construct onetime config structure from mutable settings hash
V2::MutableSettings.construct_onetime_config(@mutable_settings_hash)
#=> {:site=>{:interface=>{:ui=>{:enabled=>true, :signup=>{:enabled=>false}, :signin=>{:enabled=>true}}, :api=>{:enabled=>true}}, :secret_options=>{:anonymous=>{:max_size=>1024}, :standard=>{:max_size=>2048}, :enhanced=>{:max_size=>4096}}}, :mail=>{:validation=>{:recipients=>true, :accounts=>true}}, :limits=>{:create_secret=>500}}

## Can construct onetime config from partial mutable settings hash
partial_config = { ui: { enabled: false }, mail: { validation: { recipients: false } } }
V2::MutableSettings.construct_onetime_config(partial_config)
#=> {:site=>{:interface=>{:ui=>{:enabled=>false}}}, :mail=>{:validation=>{:recipients=>false}}}

## Can handle empty mutable settings hash
V2::MutableSettings.construct_onetime_config({})
#=> {}

## Can handle nil values in mutable settings
nil_config = { ui: { enabled: nil }, mail: nil }
result = V2::MutableSettings.construct_onetime_config(nil_config)
result.has_key?(:mail)
#=> false

## Can create a new mutable settings record
@obj = V2::MutableSettings.create(**@obj_config_data)
@obj.class
#=> V2::MutableSettings

## Created mutable settings has proper identifier
@obj.identifier.length
#=> 31

## Created mutable settings exists in Redis
V2::MutableSettings.exists?(@obj.identifier)
#=> true

## Cannot create duplicate mutable settings with same identifier
begin
  duplicate = V2::MutableSettings.new
  duplicate.instance_variable_set(:@configid, @obj.identifier)
  duplicate.save
rescue OT::Problem => e
  e.message.include?("Cannot clobber V2::MutableSettings")
end
#=> true

## Can check if customer owns a mutable settings
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

## Can add mutable settings to tracking sets
V2::MutableSettings.add(@obj)
V2::MutableSettings.values.member?(@obj.identifier)
#=> true

## Can retrieve all mutable settings
all_configs = V2::MutableSettings.all
all_configs.any? { |c| c.identifier == @obj.identifier }
#=> true

## Can get current mutable settings from stack
V2::MutableSettings.current.identifier
#=> @obj.identifier

## Can create second mutable settings and it becomes current
@obj_config_data2 = {
  ui: { enabled: false },
  api: { enabled: false },
  mail: { validation: { accounts: false } },
  custid: @customer.custid,
  comment: 'Second test config'
}
@obj2 = V2::MutableSettings.create(**@obj_config_data2)
p [@obj2.identifier, V2::MutableSettings.current.identifier]
V2::MutableSettings.current.identifier
#=> @obj2.identifier

## Can get previous mutable settings from stack
V2::MutableSettings.previous.identifier
#=> @obj.identifier

## Can retrieve recent mutable settings within time window
recent_configs = V2::MutableSettings.recent(1.hour)
recent_configs.length >= 2
#=> true

## Can remove mutable settings from values set
V2::MutableSettings.rem(@obj2)
V2::MutableSettings.values.member?(@obj2.identifier)
#=> false

## Removed config still exists in Redis but not in values set
@obj2.exists?
#=> true

## Can remove bad config from both values and stack
p [:working_on, @obj2.identifier]
p [:before, V2::MutableSettings.stack.all]
V2::MutableSettings.remove_bad_config(@obj2)
p [:after, V2::MutableSettings.stack.all]
V2::MutableSettings.stack.member?(@obj2.identifier)
#=> false

## Extract settings sections handles missing nested keys gracefully
incomplete_config = { site: { interface: { ui: { enabled: true } } } }
result = V2::MutableSettings.extract_mutable_settings(incomplete_config)
result[:secret_options]
#=> nil

## Extract settings sections handles completely missing sections
minimal_config = { other_section: { value: 'test' } }
result = V2::MutableSettings.extract_mutable_settings(minimal_config)
[result[:ui], result[:mail], result[:limits]]
#=> [nil, nil, nil]

## Construct onetime config skips nil values appropriately
config_with_nils = { ui: nil, mail: { validation: { recipients: true } } }
result = V2::MutableSettings.construct_onetime_config(config_with_nils)
p [:plop, result]
[result.has_key?(:site), result.dig(:site, :interface).nil?]
#=> [false, true]

## FIELD_MAPPINGS constant is properly defined
V2::MutableSettings::FIELD_MAPPINGS.keys.sort
#=> [:api, :limits, :mail, :secret_options, :ui]

## FIELD_MAPPINGS has correct paths for nested site sections
[
  V2::MutableSettings::FIELD_MAPPINGS[:ui],
  V2::MutableSettings::FIELD_MAPPINGS[:secret_options]
]
#=> [[:site, :interface, :ui], [:site, :secret_options]]

## FIELD_MAPPINGS has correct paths for top-level sections
[
  V2::MutableSettings::FIELD_MAPPINGS[:mail],
  V2::MutableSettings::FIELD_MAPPINGS[:limits]
]
#=> [[:mail], [:limits]]

# Cleanup
@customer.destroy!
@other_customer.destroy!
