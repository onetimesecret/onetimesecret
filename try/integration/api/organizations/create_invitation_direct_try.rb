# try/integration/api/organizations/create_invitation_direct_try.rb
#
# frozen_string_literal: true

# Tests CreateInvitation logic class directly (bypassing HTTP layer)
# Useful for verifying the logic works independently of routing/middleware

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Create test instance with Rack::Test::Methods
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Delegate Rack::Test methods to @test
def post(*args); @test.post(*args); end
def last_response; @test.last_response; end

# Setup: Create customer with organization
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "direct_invite_owner_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

@org = Onetime::Organization.create!("Direct Invite Test Org", @owner, @owner.email)
@org.is_default = true
@org.save

@session = { 'authenticated' => true, 'external_id' => @owner.extid, 'email' => @owner.email }

## Emailer is configured for test mode
@emailer_conf = OT.conf.fetch('emailer', {})
@emailer_conf['mode']
#=> 'logger'

## Mailer can be reset without error
Onetime::Mail::Mailer.reset!
true
#=> true

## CreateInvitation logic class works directly
require 'apps/api/organizations/logic'

strategy_result = MockStrategyResult.new(session: @session, user: @owner)

params = {
  'extid' => @org.extid,
  'email' => "invite1_#{@timestamp}@example.com",
  'role' => 'member'
}

@logic = OrganizationAPI::Logic::Invitations::CreateInvitation.new(strategy_result, params)
@logic.raise_concerns
@result = @logic.process
@result.key?(:record)
#=> true

## Result contains the user external ID
@result[:user_id]
#=> @owner.extid

## Record has correct email
@result[:record][:email]
#=> "invite1_#{@timestamp}@example.com"

## Record has pending status
@result[:record][:status]
#=> 'pending'

# Teardown - get the actual membership from the logic instance
@membership = @logic.instance_variable_get(:@membership)
@membership&.destroy_with_index_cleanup!
@org&.destroy!
@owner&.destroy!
