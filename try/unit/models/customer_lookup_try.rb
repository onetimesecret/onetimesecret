# try/unit/models/customer_lookup_try.rb
#
# frozen_string_literal: true

# These tryouts test Customer.load_by_extid_or_email, a dual-lookup
# class method that tries find_by_extid first, then falls back to
# find_by_email. This supports API auth paths where the caller may
# supply either an extid or an email as the username.
#
# Tests cover:
# 1. Finds a customer by email
# 2. Finds a customer by extid
# 3. Returns nil for an unknown email
# 4. Returns nil for an unknown extid
# 5. Returns nil for nil/empty input

require_relative '../../support/test_helpers'

OT.boot! :test, false

@email = generate_unique_test_email("lookup")
@cust = Onetime::Customer.create!(email: @email)
@cust.save
@extid = @cust.extid

# TRYOUTS

## load_by_extid_or_email finds a customer by email
result = Onetime::Customer.load_by_extid_or_email(@email)
result.is_a?(Onetime::Customer) && result.email == @email
#=> true

## load_by_extid_or_email finds a customer by extid
result = Onetime::Customer.load_by_extid_or_email(@extid)
result.is_a?(Onetime::Customer) && result.email == @email
#=> true

## load_by_extid_or_email returns nil for an unknown email
Onetime::Customer.load_by_extid_or_email("nobody-#{SecureRandom.hex(6)}@example.com")
#=> nil

## load_by_extid_or_email returns nil for an unknown extid
Onetime::Customer.load_by_extid_or_email("ur#{SecureRandom.hex(12)}")
#=> nil

## load_by_extid_or_email returns nil for nil input
Onetime::Customer.load_by_extid_or_email(nil)
#=> nil

## load_by_extid_or_email returns nil for empty string input
Onetime::Customer.load_by_extid_or_email('')
#=> nil

## The method is defined as a class method on Customer
Onetime::Customer.respond_to?(:load_by_extid_or_email)
#=> true

# TEARDOWN

begin
  @cust.delete! if @cust&.exists?
rescue StandardError
  nil
end
