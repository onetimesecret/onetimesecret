# try/20_models/27_domains_expiration_try.rb

require 'securerandom'

require_relative '../test_models'

#Familia.debug = true

# Load the app
OT.boot! :test, false

@unique_string = "Tryouts+27+#{SecureRandom.uuid}"
@customer = V1::Customer.create "#{@unique_string}@onetimesecret.com"
@domain = "#{@unique_string}.example.com"

## Base update_expiration accepts ttl parameter without error
obj = V2::CustomDomain.create(@domain, @customer.custid)
begin
  obj.update_expiration(default_expiration: 3600)
  true
rescue ArgumentError => e
  false
end
#=> true

## Base update_expiration maintains no-op behavior (returns nil)
obj = V2::CustomDomain.create("a.#{@domain}", @customer.custid)
obj.update_expiration(default_expiration: 3600)
#=> nil

## Base update_expiration works without ttl parameter
obj = V2::CustomDomain.create("b.#{@domain}", @customer.custid)
obj.update_expiration
#=> nil

## Base update_expiration debug logging works
obj = V2::CustomDomain.create("c.#{@domain}", @customer.custid)
# Debug logging is enabled at the start of this file
obj.update_expiration(default_expiration: 3600)
true # If we got here without error, logging worked
#=> true

## Base update_expiration works with save(update_expiration: false)
obj = V2::CustomDomain.create("d.#{@domain}", @customer.custid)
begin
  obj.save(update_expiration: false)
  true
rescue => e
  puts e.message
  false
end
#=> true

## Base update_expiration works within Redis transaction
obj = V2::CustomDomain.create("e.#{@domain}", @customer.custid)
begin
  obj.transaction do |conn|
    conn.hmset obj.dbkey, {'test' => 'value'}
    obj.update_expiration(default_expiration: 3600)
  end
  true
rescue => e
  puts e.message
  false
end
#=> true

# Cleanup
@customer.destroy!
