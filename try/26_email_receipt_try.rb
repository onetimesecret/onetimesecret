# frozen_string_literal: true

# These tryouts cover various aspects of the EmailReceipt model, including:
#
# 1. Checking the correct prefix, suffix, and identifier
# 2. Verifying the rediskey format
# 3. Creating a new EmailReceipt
# 4. Checking the fields of a new EmailReceipt
# 5. Verifying existence in Redis
# 6. Testing class methods like `all` and `recent`
# 7. Checking if the EmailReceipt is added to the values sorted set
# 8. Testing the destruction process

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot! :app

# Setup some variables for these tryouts
@now = Time.now.strftime("%Y%m%d%H%M%S")
@email_address = "tryouts+#{@now}@onetimesecret.com"
@cust = OT::Customer.new @email_address

# TRYOUTS
#

# Setup for EmailReceipt tryouts
@secretid = "secret#{@now}"
@email_receipt = OT::EmailReceipt.new(secretid: @secretid, custid: @email_address)

## EmailReceipt has the correct prefix (method missing in Familia v1.0.0-rc7)
@email_receipt.prefix
##=> :secret

## EmailReceipt has the correct suffix
@email_receipt.suffix
#=> :email

## EmailReceipt uses secretid as identifier
@email_receipt.identifier
#=> @secretid

## EmailReceipt has the correct rediskey format
@email_receipt.rediskey
#=> "secret:#{@secretid}:email"

## Can create a new EmailReceipt
@new_receipt = OT::EmailReceipt.create(@email_address, @secretid, "Test message")
@new_receipt.class
#=> OT::EmailReceipt

## New EmailReceipt has correct custid
@new_receipt.custid
#=> @email_address

## New EmailReceipt has correct secretid
@new_receipt.secretid
#=> @secretid

## New EmailReceipt has correct message_response
@new_receipt.message_response
#=> "Test message"

## New EmailReceipt exists in Redis
@new_receipt.exists?
#=> true

## Can retrieve all EmailReceipts
OT::EmailReceipt.all.class
#=> Array

## Can retrieve recent EmailReceipts
OT::EmailReceipt.recent.class
#=> Array

## EmailReceipt is added to values sorted set
OT::EmailReceipt.values.member?(@new_receipt.identifier)
#=> true

## Can destroy EmailReceipt
@new_receipt.destroy!
@new_receipt.exists?
#=> false

## Destroyed EmailReceipt is removed from values sorted set
OT::EmailReceipt.values.member?(@new_receipt.identifier)
#=> false
