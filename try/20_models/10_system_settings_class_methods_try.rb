# try/20_models/10_system_settings_class_methods_try.rb

# redis-server --port 2121 --save "" --appendonly no
# clear && ONETIME_DEBUG=1 REDIS_URL='redis://127.0.0.1:2121/0' bundle exec try -vf tests/unit/ruby/try/20_models/10_system_settings_class_methods_try.rb
# REDIS_URL='redis://127.0.0.1:2121/0' ruby support/clear_redis.rb --all --force

# Testing race condition with sorted sets using low precision now:
# while true; do pnpm run redis:clean --force && pnpm run test:tryouts tests/unit/ruby/try/20_models/10_system_settings_class_methods_try.rb || break; done

require 'securerandom'
require 'fakeredis'

require_relative '../test_models'

#Familia.debug = true

# Familia.redis = Redis.new

# Load the app
OT.boot! :test, true

# Clear any existing system settings to start fresh
V2::SystemSettings.values.clear
V2::SystemSettings.stack.clear

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

@system_settings_hash = {
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

## Can extract settings sections from full config using FIELD_MAPPINGS
V2::SystemSettings.extract_system_settings(@test_config)
#=> {:interface=>{:host=>"localhost", :port=>3000, :ssl=>false}, :secret_options=>{:max_size=>1024, :default_ttl=>3600}, :mail=>{:from=>"noreply@example.com", :smtp=>{:host=>"smtp.example.com", :port=>587}}, :limits=>{:create_secret=>250, :send_feedback=>10}, :diagnostics=>{:enabled=>true, :level=>"info"}}

## Can construct onetime config structure from system settings hash
V2::SystemSettings.construct_onetime_config(@system_settings_hash)
#=> {:site=>{:interface=>{:host=>"custom.example.com", :port=>8080, :ssl=>true}, :secret_options=>{:max_size=>2048}}, :mail=>{:from=>"custom@example.com"}, :limits=>{:create_secret=>500}, :diagnostics=>{:level=>"debug"}}

## Can construct onetime config from partial system settings hash
partial_config = { interface: { host: 'partial.example.com' }, mail: { from: 'partial@example.com' } }
V2::SystemSettings.construct_onetime_config(partial_config)
#=> {:site=>{:interface=>{:host=>"partial.example.com"}}, :mail=>{:from=>"partial@example.com"}}

## Can handle empty system settings hash
V2::SystemSettings.construct_onetime_config({})
#=> {}

## Can handle nil values in system settings
nil_config = { interface: { host: nil }, mail: nil }
result = V2::SystemSettings.construct_onetime_config(nil_config)
result.has_key?(:mail)
#=> false

## Can create a new system settings record
@obj = V2::SystemSettings.create(**@obj_config_data)
@obj.class
#=> V2::SystemSettings

## Created system settings has proper identifier
@obj.identifier.length
#=> 31

## Created system settings exists in Redis
V2::SystemSettings.exists?(@obj.identifier)
#=> true

## Cannot create duplicate system settings with same identifier
begin
  duplicate = V2::SystemSettings.new
  duplicate.instance_variable_set(:@configid, @obj.identifier)
  duplicate.save
rescue OT::Problem => e
  e.message.include?("Cannot clobber V2::SystemSettings")
end
#=> true

## Can check if customer owns a system settings
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

## Can add system settings to tracking sets
V2::SystemSettings.add(@obj)
V2::SystemSettings.values.member?(@obj.identifier)
#=> true

## Can retrieve all system settings
all_configs = V2::SystemSettings.all
all_configs.any? { |c| c.identifier == @obj.identifier }
#=> true

## Can get current system settings from stack
V2::SystemSettings.current.identifier
#=> @obj.identifier

## Can create second system settings and it becomes current
@obj_config_data2 = {
  interface: { host: 'second.example.com', port: 8000 },
  mail: { from: 'second@example.com' },
  custid: @customer.custid,
  comment: 'Second test config'
}
@obj2 = V2::SystemSettings.create(**@obj_config_data2)
p [@obj2.identifier, V2::SystemSettings.current.identifier]
V2::SystemSettings.current.identifier
#=> @obj2.identifier

## Can get previous system settings from stack
V2::SystemSettings.previous.identifier
#=> @obj.identifier

## Can retrieve recent system settings within time window
recent_configs = V2::SystemSettings.recent(1.hour)
recent_configs.length >= 2
#=> true

## Can remove system settings from values set
V2::SystemSettings.rem(@obj2)
V2::SystemSettings.values.member?(@obj2.identifier)
#=> false

## Removed config still exists in Redis but not in values set
@obj2.exists?
#=> true

## Can remove bad config from both values and stack
p [:working_on, @obj2.identifier]
p [:before, V2::SystemSettings.stack.all]
V2::SystemSettings.remove_bad_config(@obj2)
p [:after, V2::SystemSettings.stack.all]
V2::SystemSettings.stack.member?(@obj2.identifier)
#=> false

## Extract settings sections handles missing nested keys gracefully
incomplete_config = { site: { interface: { host: 'test' } } }
result = V2::SystemSettings.extract_system_settings(incomplete_config)
result[:secret_options]
#=> nil

## Extract settings sections handles completely missing sections
minimal_config = { other_section: { value: 'test' } }
result = V2::SystemSettings.extract_system_settings(minimal_config)
[result[:interface], result[:mail], result[:limits]]
#=> [nil, nil, nil]

## Construct onetime config skips nil values appropriately
config_with_nils = { interface: nil, mail: { from: 'test@example.com' } }
result = V2::SystemSettings.construct_onetime_config(config_with_nils)
p [:plop, result]
[result.has_key?(:site), result.dig(:site, :interface).nil?]
#=> [false, true]

## FIELD_MAPPINGS constant is properly defined
V2::SystemSettings::FIELD_MAPPINGS.keys.sort
#=> [:diagnostics, :interface, :limits, :mail, :secret_options]

## FIELD_MAPPINGS has correct paths for nested site sections
[
  V2::SystemSettings::FIELD_MAPPINGS[:interface],
  V2::SystemSettings::FIELD_MAPPINGS[:secret_options]
]
#=> [[:site, :interface], [:site, :secret_options]]

## FIELD_MAPPINGS has correct paths for top-level sections
[
  V2::SystemSettings::FIELD_MAPPINGS[:mail],
  V2::SystemSettings::FIELD_MAPPINGS[:limits]
]
#=> [[:mail], [:limits]]

# Cleanup
@customer.destroy!
@other_customer.destroy!
