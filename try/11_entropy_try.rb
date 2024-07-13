# frozen_string_literal: true

# These tryouts test the functionality of the OT::Entropy module.
# The Entropy module is responsible for generating and managing
# random values used throughout the Onetime application.
#
# We're testing various aspects of the Entropy module, including:
# 1. Generating and clearing entropy values
# 2. Counting available entropy values
# 3. Popping values from the entropy pool
#
# These tests aim to ensure that the entropy generation and management
# in the Onetime application works correctly, which is crucial for
# maintaining security and unpredictability in various operations.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :cli

## Clear values
OT::Entropy.generate 2
OT::Entropy.values.clear
#=> 1

## Try to clear values when there are none
OT::Entropy.values.clear
#=> 0

## Knows the count
OT::Entropy.count
#=> 0

## Can pop a value even when empty
val = OT::Entropy.pop
[val.size, val.class]
#=> [12, String]

## Can generate values
OT::Entropy.generate 10
#=> 10

## Still knows the count
OT::Entropy.count
#=> 10

## Can pop a value even when empty
val = OT::Entropy.pop
[val.size, val.class]
#=> [12, String]

## Still knows the count
OT::Entropy.count
#=> 9
