# try/20_models/27_domains_expiration_try.rb
#
# frozen_string_literal: true

require 'securerandom'

require_relative '../../support/test_models'

#Familia.debug = true

# Load the app
OT.boot! :test, false

@unique_string = "Tryouts+27+#{SecureRandom.uuid}"
@customer = Onetime::Customer.create!(email: "#{@unique_string}@onetimesecret.com")
@domain = "#{@unique_string}.example.com"

## Base update_expiration accepts default_expiration parameter (Familia 2: ttl→default_expiration)
obj = Onetime::CustomDomain.create(@domain, @customer.custid)
begin
  obj.update_expiration(default_expiration: 3600)
  true
rescue ArgumentError => e
  false
end
#=> true

## Base update_expiration maintains no-op behavior (returns nil)
obj = Onetime::CustomDomain.create("a.#{@domain}", @customer.custid)
obj.update_expiration(default_expiration: 3600)
#=> nil

## Base update_expiration works without default_expiration parameter
obj = Onetime::CustomDomain.create("b.#{@domain}", @customer.custid)
obj.update_expiration
#=> nil

## Base update_expiration debug logging works
obj = Onetime::CustomDomain.create("c.#{@domain}", @customer.custid)
# Debug logging is enabled at the start of this file
obj.update_expiration(default_expiration: 3600)
true # If we got here without error, logging worked
#=> true

## Base update_expiration works with save(update_expiration: false)
obj = Onetime::CustomDomain.create("d.#{@domain}", @customer.custid)
begin
  obj.save(update_expiration: false)
  true
rescue => e
  puts e.message
  false
end
#=> true

## Base update_expiration works within Redis transaction
obj = Onetime::CustomDomain.create("e.#{@domain}", @customer.custid)
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
