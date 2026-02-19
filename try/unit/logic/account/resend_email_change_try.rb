# try/unit/logic/account/resend_email_change_try.rb
#
# frozen_string_literal: true

# These tryouts test the ResendEmailChangeConfirmation logic:
#
# 1. Raises error when secret expired/deleted and cleans up stale reference
# 2. Raises rate_limited error after MAX_RESENDS reached
# 3. Successful resend increments count and enqueues email
# 4. success_data returns expected shape
# 5. resend_count_key is scoped to customer objid with 24h TTL

require_relative '../../../support/test_logic'

OT.boot! :test, false

@password = 'testresend123'
@session = {}
@email_address = generate_unique_test_email('resend')
@cust = Onetime::Customer.new email: @email_address
@cust.update_passphrase @password
@cust.save

@strategy_result = MockStrategyResult.new(session: @session, user: @cust)

# Helper to set up a pending email change for the customer
def setup_pending_change(cust, new_email)
  secret = Onetime::Secret.create!(owner_id: cust.objid)
  secret.default_expiration = 86_400 # 24 hours
  secret.verification = 'true'
  secret.custid = cust.objid
  secret.ciphertext = new_email
  secret.save
  cust.pending_email_change = secret.identifier
  secret
end

def clear_resend_counter(cust)
  Familia.dbclient.del("email_change_resend:#{cust.objid}")
end

# TRYOUTS

## Raises expired error when secret has been deleted
stale_email = generate_unique_test_email('resend-stale')
stale_secret = setup_pending_change(@cust, stale_email)
stale_secret.delete!
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Email change request has expired']

## Raises expired error for non-verification secret
non_verif_email = generate_unique_test_email('resend-nonverif')
secret = Onetime::Secret.create!(owner_id: @cust.objid)
secret.default_expiration = 86_400
secret.verification = 'false'
secret.custid = @cust.objid
secret.save
@cust.pending_email_change = secret.identifier
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Email change request has expired']

## Raises rate_limited error after MAX_RESENDS reached
rate_email = generate_unique_test_email('resend-rate')
setup_pending_change(@cust, rate_email)
key = "email_change_resend:#{@cust.objid}"
Familia.dbclient.set(key, AccountAPI::Logic::Account::ResendEmailChangeConfirmation::MAX_RESENDS.to_s, ex: 3600)
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Maximum resend limit (3) reached']

## Successful resend returns sent:true with resend count
clear_resend_counter(@cust)
resend_email = generate_unique_test_email('resend-ok')
setup_pending_change(@cust, resend_email)
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
obj.raise_concerns
result = obj.process
[result[:sent], result[:resend_count]]
#=> [true, 1]

## Second resend increments count to 2
obj2 = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
obj2.raise_concerns
result2 = obj2.process
result2[:resend_count]
#=> 2

## Third resend increments count to 3 (final allowed)
obj3 = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
obj3.raise_concerns
result3 = obj3.process
result3[:resend_count]
#=> 3

## Fourth resend attempt is rate limited
obj4 = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
begin
  obj4.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Maximum resend limit (3) reached']

## success_data returns expected shape with sent and resend_count keys
clear_resend_counter(@cust)
fresh_email = generate_unique_test_email('resend-shape')
setup_pending_change(@cust, fresh_email)
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
obj.raise_concerns
data = obj.success_data
[data.key?(:sent), data.key?(:resend_count)]
#=> [true, true]

## resend_count_key is scoped to customer objid
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
key = obj.send(:resend_count_key)
key
#=> "email_change_resend:#{@cust.objid}"

## resend_count_key TTL is set to 24 hours after first increment
clear_resend_counter(@cust)
ttl_email = generate_unique_test_email('resend-ttl')
setup_pending_change(@cust, ttl_email)
obj = AccountAPI::Logic::Account::ResendEmailChangeConfirmation.new @strategy_result, {}
obj.raise_concerns
obj.process
ttl = Familia.dbclient.ttl("email_change_resend:#{@cust.objid}")
ttl > 86_000 && ttl <= 86_400
#=> true

# Cleanup
clear_resend_counter(@cust)
@cust.pending_email_change.delete! rescue nil
@cust.delete!
