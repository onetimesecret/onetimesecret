# frozen_string_literal: true

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.load! :app

# Setup some variables for these tryouts
@now = DateTime.now
@model_class = OT::Customer
@email_address = "tryouts+#{@now}@onetimesecret.com"
@cust = OT::Customer.new @email_address

# TRYOUTS

## New instance of customer has no planid (not saved yet)
@cust.planid
#=> nil

## New instance of customer has a custid
@cust.custid
#=> @email_address

## New instance of customer has a rediskey
@cust.rediskey
#=> "customer:#{@email_address}:object"

## Object name and rediskey are equivalent
@cust.rediskey.eql?(@cust.name)
#=> true
