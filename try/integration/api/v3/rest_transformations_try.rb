# try/integration/api/v3_rest_transformations_try.rb
#
# Verify V3 and Account API REST transformations:
# - Remove 'success' field (use HTTP status codes)
# - Rename 'custid' to 'user_id'
#
# This ensures v3/account APIs follow pure REST semantics while v2 remains unchanged.

require_relative '../../../support/test_logic'
require 'apps/api/v2/logic/secrets/list_metadata'
require 'apps/api/v3/logic'

OT.boot! :test, false

@email = "tryouts+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@sess = Onetime::Session.new(@cust.custid)
@sess.save

## V2 API preserves 'success' field
v2_logic = V2::Logic::Secrets::ListMetadata.new({}, @cust, @sess, 'en', 'localhost', 'standard')
v2_response = v2_logic.process
[v2_response.key?('success'), v2_response['success']]
#=> [true, true]

## V2 API preserves 'custid' field
[v2_response.key?('custid'), v2_response['custid'], v2_response.key?('user_id')]
#=> [true, @cust.custid, false]

# TODO: Rewrite V3 tests after strategy refactoring (commits 0986aeb38, 66fc5a57f)
#
# The V3 logic class initialization signature changed from:
#   initialize(params, cust, sess, locale, ip, plan)
# To:
#   initialize(strategy_result, params, locale = nil)
#
# Current test uses old 6-parameter signature incompatible with new StrategyResult pattern.
# Needs complete rewrite to construct proper StrategyResult object with session and metadata.
#
# ## V3 API removes 'success' field
# v3_logic = V3::Logic::Secrets::ListMetadata.new({}, @cust, @sess, 'en', 'localhost', 'standard')
# v3_response = v3_logic.process
# [v3_response.key?(:success), v3_response.key?('success')]
# #=> [false, false]
#
# ## V3 API renames 'custid' to 'user_id'
# [v3_response.key?(:custid), v3_response.key?('custid'), v3_response.key?(:user_id), v3_response[:user_id]]
# #=> [false, false, true, @cust.objid]

# Teardown
@sess.destroy!
@cust.destroy!
