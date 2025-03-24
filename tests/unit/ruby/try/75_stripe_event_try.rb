# tests/unit/ruby/try/75_stripe_event_try.rb

# frozen_string_literal: true

# These tryouts test the StripeEvent model functionality in the OneTime application.
# They cover various aspects of Stripe event management, including:
#
# 1. StripeEvent creation and initialization
# 2. StripeEvent attributes (custid, eventid, message_response, etc.)
# 3. Redis key format and storage
# 4. Class methods for retrieving and managing events
# 5. Destruction process
#
# These tests aim to verify the correct behavior of the OT::StripeEvent class,
# which is essential for managing Stripe-related events in the application.

require_relative './test_helpers'
require 'onetime/models/stripe_event'

# Load the app
OT.boot! :test

# Setup
def setup
  @now = Time.now.strftime("%Y%m%d%H%M%S")
  @custid = "customer_#{@now}"
  @eventid = "evt_#{@now}"

  @message_response = "Test message response"
  @stripe_event = OT::StripeEvent.new(eventid: @eventid, custid: @custid, message_response: @message_response)
end

# Teardown
def teardown
  @stripe_event.destroy! if @stripe_event && @stripe_event.exists?
end

# TRYOUTS

setup

## New instance of StripeEvent has the correct prefix
@stripe_event.prefix
##=> :stripe

## New instance of StripeEvent has the correct suffix
@stripe_event.suffix
#=> :object

## New instance of StripeEvent has the correct identifier
@stripe_event.identifier
#=> @eventid

## New instance of StripeEvent has the correct rediskey format
@stripe_event.rediskey
#=> "stripeevent:#{@eventid}:object"

## New instance of StripeEvent has the correct custid
@stripe_event.custid
#=> @custid

## New instance of StripeEvent has the correct message_response
@stripe_event.message_response
#=> @message_response

## Can create a new StripeEvent
p [@eventid, @custid, @message_response]
@new_event = OT::StripeEvent.new(eventid: @eventid, custid: @custid, message_response: @message_response)
@new_event.class
#=> OT::StripeEvent

## New StripeEvent doesn't exist in Redis yet
@new_event.exists?
#=> false

## New StripeEvent doesn't exist in Redis yet
@new_event.save
@new_event.exists?
#=> true

## Can retrieve all StripeEvents
OT::StripeEvent.all.class
#=> Array

## Can retrieve recent StripeEvents
OT::StripeEvent.recent.class
#=> Array

## StripeEvent is not added to values sorted set automatically (when created using new + save)
OT::StripeEvent.values.member?(@new_event.identifier)
#=> false

## StripeEvent is added to values sorted set
OT::StripeEvent.add @new_event
OT::StripeEvent.values.member?(@new_event.identifier)
#=> true

## Can destroy StripeEvent
@new_event.destroy!
@new_event.exists?
#=> false

## Destroyed StripeEvent is removed from values sorted set
OT::StripeEvent.values.member?(@new_event.identifier)
#=> false

teardown
