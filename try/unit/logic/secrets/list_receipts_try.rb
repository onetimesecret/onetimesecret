# try/unit/logic/secrets/list_receipts_try.rb
#
# frozen_string_literal: true

# Tests for V2::Logic::Secrets::ListReceipts#raise_concerns
#
# The nil guard on line 43 ensures anonymous (unauthenticated) users get
# a RecordNotFound error rather than a NoMethodError crash on nil.custid.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@email = generate_unique_test_email("list_receipts")
@cust = Onetime::Customer.create!(email: @email)
@sess = MockSession.new
@auth_result = MockStrategyResult.authenticated(@cust, session: @sess)
@anon_result = MockStrategyResult.anonymous

## Raises RecordNotFound when no authenticated customer (anonymous user)
logic = Logic::Secrets::ListReceipts.new(@anon_result, {}, 'en')
logic.process_params
begin
  logic.raise_concerns
  :no_error
rescue Onetime::RecordNotFound
  :not_found
end
#=> :not_found

## Does not raise RecordNotFound for authenticated customer
logic = Logic::Secrets::ListReceipts.new(@auth_result, {}, 'en')
logic.process_params
begin
  logic.raise_concerns
  :no_error
rescue Onetime::RecordNotFound
  :not_found
end
#=> :no_error

## Anonymous user cust is nil
logic = Logic::Secrets::ListReceipts.new(@anon_result, {}, 'en')
logic.cust.nil?
#=> true

# TEARDOWN

@cust.delete! if @cust&.exists?
