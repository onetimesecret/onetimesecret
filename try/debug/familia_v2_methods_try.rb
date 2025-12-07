# try/debug/familia_v2_methods_try.rb
#
# frozen_string_literal: true

#
# Debug what methods are available from participates_in
#

require_relative '../support/test_models'


OT.boot! :test

@owner = Onetime::Customer.create!(email: "debug_#{Familia.now.to_i}@test.com")
@org = Onetime::Organization.new(display_name: "Test", owner_id: @owner.custid, contact_email: "test@test.com")
@org.save

## Check Organization methods for members
puts "Organization members methods:"
puts @org.methods.grep(/members/).sort.join("\n")
puts ""
puts "Customer organization methods:"
puts @owner.methods.grep(/organization/).sort.join("\n")
true
#=> true

# Teardown
@org.destroy!
@owner.destroy!
