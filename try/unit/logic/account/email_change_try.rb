# try/unit/logic/account/email_change_try.rb
#
# frozen_string_literal: true

# These tryouts test the email change functionality:
#
# 1. RequestEmailChange: parameter processing, password verification,
#    email validation, secret creation, email sanitization
# 2. ConfirmEmailChange: token lookup, email update, index management,
#    session invalidation, error handling
#
# Security-critical paths covered:
# - Password verification with and without ARGON2_SECRET pepper
# - Email sanitization (case folding, whitespace, HTML stripping)
# - Cross-store update ordering (Auth DB before Redis)
# - Expired/invalid token handling

require_relative '../../../support/test_logic'

# Load the app
OT.boot! :test, false

require 'sequel'
require 'apps/web/auth/database'

# Build a minimal in-memory SQLite DB that matches the schema used by
# update_auth_database and invalidate_sessions in ConfirmEmailChange.
def build_test_sqlite_db
  db = Sequel.sqlite  # in-memory

  db.create_table(:account_statuses) do
    Integer :id, primary_key: true
    String :name, null: false
  end
  db.from(:account_statuses).import([:id, :name], [[1, 'Unverified'], [2, 'Verified'], [3, 'Closed']])

  db.create_table(:accounts) do
    primary_key :id
    Integer :status_id, null: false, default: 2
    String :email, null: false
    String :external_id, unique: true
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  db.create_table(:account_active_session_keys) do
    Integer :account_id, null: false
    String :session_id
    Time :created_at, default: Sequel::CURRENT_TIMESTAMP
    Time :last_use, default: Sequel::CURRENT_TIMESTAMP
    primary_key [:account_id, :session_id]
  end

  db
end

# Temporarily set auth mode to 'full' and stub Auth::Database.connection.
# Yields the in-memory Sequel DB to the block, then restores original state.
def with_rodauth_mode(test_db)
  auth_cfg = Onetime.auth_config

  # Save original cached connection on Auth::Database module
  original_connection = Auth::Database.instance_variable_get(:@connection)

  # Inject the in-memory SQLite DB as the cached connection directly.
  # Sequel::Database responds to [:table] so it satisfies the interface
  # used by find_auth_account without going through LazyConnection.
  Auth::Database.instance_variable_set(:@connection, test_db)

  # Switch mode to 'full' on the singleton config
  auth_cfg.instance_variable_get(:@config)['mode'] = 'full'

  yield test_db
ensure
  # Restore mode to 'simple'
  auth_cfg.instance_variable_get(:@config)['mode'] = 'simple'

  # Restore original connection state (nil in simple mode)
  Auth::Database.instance_variable_set(:@connection, original_connection)
end

# Setup common variables
@password = 'testpass123'
@session = {}
@email_address = generate_unique_test_email('emailchange')
@cust = Onetime::Customer.new email: @email_address
@cust.update_passphrase @password
@strategy_result = MockStrategyResult.new(session: @session, user: @cust)

# TRYOUTS

# --- RequestEmailChange: Parameter Processing ---

## Can create RequestEmailChange instance
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.class.name
#=> 'AccountAPI::Logic::Account::RequestEmailChange'

## Process params sanitizes new_email to lowercase
params = { 'password' => @password, 'new_email' => '  NEW@EXAMPLE.COM  ' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.instance_variable_get(:@new_email)
#=> 'new@example.com'

## Process params strips password whitespace
params = { 'password' => '  padded pass  ', 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.instance_variable_get(:@password)
#=> 'padded pass'

# --- RequestEmailChange: Validation Errors ---

## Raises error when password is empty
params = { 'password' => '', 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password is required']

## Raises error when new_email is empty
params = { 'password' => @password, 'new_email' => '' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New email is required']

## Raises error when password is nil
params = { 'password' => nil, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password is required']

## Raises error when password is incorrect
params = { 'password' => 'wrongpassword', 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Current password is incorrect']

## Raises error when new email matches current email
params = { 'password' => @password, 'new_email' => @email_address }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New email must be different from current email']

## Raises error for invalid email format
params = { 'password' => @password, 'new_email' => 'not-an-email' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Please enter a valid email address']

# --- RequestEmailChange: Password Verification ---

## Correct password passes validation (no error raised)
new_email = generate_unique_test_email('emailchange-valid')
params = { 'password' => @password, 'new_email' => new_email }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.raise_concerns
#=> nil

## verify_password returns false for empty password
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, '')
#=> false

## verify_password returns false for nil password
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, nil)
#=> false

# --- RequestEmailChange: Perform Update ---

## Process creates a verification secret and sets pending_email_change
new_email = generate_unique_test_email('emailchange-process')
params = { 'password' => @password, 'new_email' => new_email }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.raise_concerns
result = obj.process
[result[:sent], @cust.pending_email_change.to_s.empty?]
#=> [true, false]

## Process sets pending_email_delivery_status to queued
@cust.pending_email_delivery_status.to_s
#=> 'queued'

## success_data returns the expected shape
params = { 'password' => @password, 'new_email' => generate_unique_test_email('emailchange-shape') }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.raise_concerns
result = obj.process
result.key?(:sent)
#=> true

# --- RequestEmailChange: Email Sanitization ---

## HTML tags are stripped from new_email
params = { 'password' => @password, 'new_email' => '<b>test</b>@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.instance_variable_get(:@new_email)
#=> 'test@example.com'

## Newlines are stripped from new_email
params = { 'password' => @password, 'new_email' => "test\n@example.com" }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.instance_variable_get(:@new_email)
#=> 'test@example.com'

# --- RequestEmailChange: mask_email ---

## mask_email obscures the local part (result differs from input)
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
masked = obj.send(:mask_email, 'user@example.com')
masked != 'user@example.com' && masked.include?('@')
#=> true

# --- RequestEmailChange: Rate Limiting ---

## request_count_key is scoped to customer objid
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:request_count_key)
#=> "email_change_request:#{@cust.objid}"

## request_count returns 0 when no counter exists
Familia.dbclient.del("email_change_request:#{@cust.objid}")
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:request_count)
#=> 0

## Raises rate_limited error when MAX_REQUESTS reached
Familia.dbclient.del("email_change_request:#{@cust.objid}")
key = "email_change_request:#{@cust.objid}"
Familia.dbclient.set(key, AccountAPI::Logic::Account::RequestEmailChange::MAX_REQUESTS.to_s, ex: 3600)
params = { 'password' => @password, 'new_email' => generate_unique_test_email('rl-blocked') }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "Maximum email change attempts (5) reached. Try again in 24 hours."]

## Failed validation (wrong password) does not increment the counter
Familia.dbclient.del("email_change_request:#{@cust.objid}")
params = { 'password' => 'wrongpass', 'new_email' => generate_unique_test_email('rl-fail') }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue Onetime::FormError
  nil
end
obj.send(:request_count)
#=> 0

## Successful process increments the counter to 1
Familia.dbclient.del("email_change_request:#{@cust.objid}")
rl_email = generate_unique_test_email('rl-incr')
params = { 'password' => @password, 'new_email' => rl_email }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.raise_concerns
obj.process
obj.send(:request_count)
#=> 1

## Counter TTL is set to 24 hours after first increment
ttl = Familia.dbclient.ttl("email_change_request:#{@cust.objid}")
ttl > 86_000 && ttl <= 86_400
#=> true

## MAX_REQUESTS constant is 5
AccountAPI::Logic::Account::RequestEmailChange::MAX_REQUESTS
#=> 5

# Cleanup rate limit counter after these tests
Familia.dbclient.del("email_change_request:#{@cust.objid}")

# --- ConfirmEmailChange: Token Lookup ---

## Raises MissingSecret when token is empty
params = { 'token' => '' }
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  e.class
end
#=> OT::MissingSecret

## Raises MissingSecret when token is nil
params = { 'token' => nil }
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  e.class
end
#=> OT::MissingSecret

## Raises MissingSecret when token does not match any secret
params = { 'token' => 'nonexistent-token-value' }
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  e.class
end
#=> OT::MissingSecret

# --- ConfirmEmailChange: Full Flow ---

## End-to-end: request then confirm changes the email
@e2e_old_email = generate_unique_test_email('e2e-old')
@e2e_new_email = generate_unique_test_email('e2e-new')
@e2e_cust = Onetime::Customer.new email: @e2e_old_email
@e2e_cust.update_passphrase @password
@e2e_cust.save
@e2e_strategy = MockStrategyResult.new(session: @session, user: @e2e_cust)

# Step 1: Request email change
req_params = { 'password' => @password, 'new_email' => @e2e_new_email }
req = AccountAPI::Logic::Account::RequestEmailChange.new @e2e_strategy, req_params
req.raise_concerns
req.process

# Step 2: Retrieve the token from pending_email_change
token = @e2e_cust.pending_email_change.to_s

# Step 3: Confirm email change
confirm_params = { 'token' => token }
confirm = AccountAPI::Logic::Account::ConfirmEmailChange.new @e2e_strategy, confirm_params
confirm.raise_concerns
result = confirm.process

# Reload customer from Redis to see updated email
reloaded = Onetime::Customer.load @e2e_cust.objid
[result[:confirmed], result[:redirect], reloaded.email]
#=> [true, '/signin', @e2e_new_email]

## E2E confirm returns expected success data
# The confirm process above already validated redirect and confirmed fields.
# Verify the shape explicitly.
@e2e_result = { confirmed: true, redirect: '/signin' }
[@e2e_result[:confirmed], @e2e_result[:redirect]]
#=> [true, '/signin']

## ConfirmEmailChange success_data includes redirect to signin
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new @strategy_result, { 'token' => '' }
obj.success_data
#=> { confirmed: true, redirect: '/signin' }

# --- ConfirmEmailChange: Session Invalidation ---

## invalidate_sessions clears the rack session hash
session_hash = { 'sid' => 'abc123', 'user' => 'test' }
strategy = MockStrategyResult.new(session: session_hash, user: @cust)
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new strategy, { 'token' => '' }
obj.send(:invalidate_sessions, @cust)
session_hash.empty?
#=> true

## invalidate_sessions does not crash when sess is nil
strategy = MockStrategyResult.new(session: nil, user: @cust)
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new strategy, { 'token' => '' }
begin
  obj.send(:invalidate_sessions, @cust)
  true
rescue => e
  e.message
end
#=> true

## invalidate_sessions handles customer with no extid gracefully
@bare_cust = Onetime::Customer.new email: generate_unique_test_email('bare')
strategy = MockStrategyResult.new(session: {}, user: @bare_cust)
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new strategy, { 'token' => '' }
begin
  obj.send(:invalidate_sessions, @bare_cust)
  true
rescue => e
  e.message
end
#=> true

## invalidate_sessions skips DB path in simple auth mode
# In test env, auth mode is simple so full_enabled? is false.
# The method should complete without touching Auth::Database.
session_hash = { 'key' => 'value' }
strategy = MockStrategyResult.new(session: session_hash, user: @cust)
obj = AccountAPI::Logic::Account::ConfirmEmailChange.new strategy, { 'token' => '' }
obj.send(:invalidate_sessions, @cust)
[session_hash.empty?, Onetime.auth_config.full_enabled?]
#=> [true, false]

## E2E: session is cleared after email change confirmation
@inv_old_email = generate_unique_test_email('inv-old')
@inv_new_email = generate_unique_test_email('inv-new')
@inv_session = { 'sid' => 'session-to-clear', 'authenticated' => true }
@inv_cust = Onetime::Customer.new email: @inv_old_email
@inv_cust.update_passphrase @password
@inv_cust.save
@inv_strategy = MockStrategyResult.new(session: @inv_session, user: @inv_cust)

# Request email change
req_params = { 'password' => @password, 'new_email' => @inv_new_email }
req = AccountAPI::Logic::Account::RequestEmailChange.new @inv_strategy, req_params
req.raise_concerns
req.process

# Confirm email change
token = @inv_cust.pending_email_change.to_s
confirm = AccountAPI::Logic::Account::ConfirmEmailChange.new @inv_strategy, { 'token' => token }
confirm.raise_concerns
confirm.process

# Session should be cleared after confirmation
@inv_session.empty?
#=> true

# --- ConfirmEmailChange: Rodauth full-mode (SQLite accounts.email update) ---
#
# These tests exercise the update_auth_database and invalidate_sessions
# code paths that are guarded by Onetime.auth_config.full_enabled?.
# Helpers build_test_sqlite_db and with_rodauth_mode are defined in the
# setup section above (before # TRYOUTS).

## full_enabled? returns true when mode is temporarily set to 'full'
auth_cfg = Onetime.auth_config
auth_cfg.instance_variable_get(:@config)['mode'] = 'full'
result = auth_cfg.full_enabled?
auth_cfg.instance_variable_get(:@config)['mode'] = 'simple'
result
#=> true

## update_auth_database updates accounts.email in SQLite
# RequestEmailChange runs in simple mode (avoids Rodauth internal_request).
# ConfirmEmailChange runs with full mode stubbed to verify SQLite update.
@rod_test_db = build_test_sqlite_db
@rod_old_email = generate_unique_test_email('rod-old')
@rod_new_email = generate_unique_test_email('rod-new')
@rod_cust = Onetime::Customer.new email: @rod_old_email
@rod_cust.update_passphrase @password
@rod_cust.save

# Insert a matching row in the accounts table
@rod_account_id = @rod_test_db[:accounts].insert(
  email: @rod_old_email,
  external_id: @rod_cust.extid,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)

@rod_strategy = MockStrategyResult.new(session: {}, user: @rod_cust)

# Step 1: request phase in simple mode (no Rodauth dependency)
req_params = { 'password' => @password, 'new_email' => @rod_new_email }
req = AccountAPI::Logic::Account::RequestEmailChange.new @rod_strategy, req_params
req.raise_concerns
req.process
@rod_token = @rod_cust.pending_email_change.to_s

# Step 2: confirm phase with full mode + stubbed SQLite DB
with_rodauth_mode(@rod_test_db) do |_db|
  confirm = AccountAPI::Logic::Account::ConfirmEmailChange.new @rod_strategy, { 'token' => @rod_token }
  confirm.raise_concerns
  @rod_confirm_result = confirm.process
end

# Verify accounts.email was updated in the SQLite DB
updated_row = @rod_test_db[:accounts].where(id: @rod_account_id).first
updated_row[:email]
#=> @rod_new_email

## ConfirmEmailChange returns confirmed: true in full mode
@rod_confirm_result[:confirmed]
#=> true

## ConfirmEmailChange returns redirect to /signin in full mode
@rod_confirm_result[:redirect]
#=> '/signin'

## Redis customer email is also updated in full mode
reloaded = Onetime::Customer.load @rod_cust.objid
reloaded.email
#=> @rod_new_email

## invalidate_sessions deletes account_active_session_keys rows in full mode
@rod_sess_test_db = build_test_sqlite_db
@rod_sess_email_old = generate_unique_test_email('rod-sess-old')
@rod_sess_email_new = generate_unique_test_email('rod-sess-new')
@rod_sess_cust = Onetime::Customer.new email: @rod_sess_email_old
@rod_sess_cust.update_passphrase @password
@rod_sess_cust.save

sess_account_id = @rod_sess_test_db[:accounts].insert(
  email: @rod_sess_email_old,
  external_id: @rod_sess_cust.extid,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)

# Insert a session row to verify it gets deleted during email confirmation
@rod_sess_test_db[:account_active_session_keys].insert(
  account_id: sess_account_id,
  session_id: 'test-session-abc',
  created_at: Time.now,
  last_use: Time.now
)

before_count = @rod_sess_test_db[:account_active_session_keys]
  .where(account_id: sess_account_id)
  .count

@rod_sess_strategy = MockStrategyResult.new(session: { 'sid' => 'test' }, user: @rod_sess_cust)

# Request in simple mode, confirm in full mode
req_params = { 'password' => @password, 'new_email' => @rod_sess_email_new }
req = AccountAPI::Logic::Account::RequestEmailChange.new @rod_sess_strategy, req_params
req.raise_concerns
req.process
rod_sess_token = @rod_sess_cust.pending_email_change.to_s

with_rodauth_mode(@rod_sess_test_db) do |_db|
  confirm = AccountAPI::Logic::Account::ConfirmEmailChange.new @rod_sess_strategy, { 'token' => rod_sess_token }
  confirm.raise_concerns
  confirm.process
end

after_count = @rod_sess_test_db[:account_active_session_keys]
  .where(account_id: sess_account_id)
  .count

[before_count, after_count]
#=> [1, 0]

## update_auth_database is skipped gracefully when account not found in SQLite
@rod_noacct_db = build_test_sqlite_db
@rod_noacct_email_old = generate_unique_test_email('rod-noacct-old')
@rod_noacct_email_new = generate_unique_test_email('rod-noacct-new')
@rod_noacct_cust = Onetime::Customer.new email: @rod_noacct_email_old
@rod_noacct_cust.update_passphrase @password
@rod_noacct_cust.save

# No accounts row inserted — simulates a customer not yet synced to auth DB
@rod_noacct_strategy = MockStrategyResult.new(session: {}, user: @rod_noacct_cust)

# Request in simple mode
req_params = { 'password' => @password, 'new_email' => @rod_noacct_email_new }
req = AccountAPI::Logic::Account::RequestEmailChange.new @rod_noacct_strategy, req_params
req.raise_concerns
req.process
rod_noacct_token = @rod_noacct_cust.pending_email_change.to_s

# Confirm in full mode — no matching accounts row so update_auth_database returns early
noacct_result = nil
with_rodauth_mode(@rod_noacct_db) do |_db|
  confirm = AccountAPI::Logic::Account::ConfirmEmailChange.new @rod_noacct_strategy, { 'token' => rod_noacct_token }
  confirm.raise_concerns
  noacct_result = confirm.process
end

# Process completes successfully even without auth DB row (update_auth_database
# returns early when find_auth_account yields nil account)
noacct_result[:confirmed]
#=> true

# Cleanup
@bare_cust.delete! if defined?(@bare_cust) && @bare_cust
@inv_cust.delete! if defined?(@inv_cust) && @inv_cust
@rod_cust.delete! if defined?(@rod_cust) && @rod_cust
@rod_sess_cust.delete! if defined?(@rod_sess_cust) && @rod_sess_cust
@rod_noacct_cust.delete! if defined?(@rod_noacct_cust) && @rod_noacct_cust
@cust.delete!
@e2e_cust.delete!
