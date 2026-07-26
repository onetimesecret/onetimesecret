# try/unit/logic/authentication/authenticate_session_try.rb
#
# frozen_string_literal: true

# These tests cover the AuthenticateSession logic class which handles
# session authentication.

require_relative '../../../support/test_logic'

# Load the app with test configuration
OT.boot! :test, true

# Load Core::Logic::Authentication which contains AuthenticateSession
require 'web/core/logic/authentication'

# Alias for cleaner test code
Auth = Core::Logic::Authentication

# Setup common test variables
@now = Familia.now
@testpass = 'test-password-12345'

# #3516 spies: count customer lookups and passphrase comparisons so the locked
# tests can prove the path short-circuits before either. Prepend so `super`
# still runs the real implementation on the happy / wrong-password paths.
# Defined here in the top setup region because loose code between test blocks
# is NOT executed by tryouts.
$find_by_email_calls = []
$passphrase_calls    = 0

module FindByEmailSpy
  def find_by_email(*args)
    $find_by_email_calls << args.first
    super
  end
end
Onetime::Customer.singleton_class.prepend(FindByEmailSpy)

module PassphraseSpy
  def passphrase?(*args)
    $passphrase_calls += 1
    super
  end
end
Onetime::Customer.prepend(PassphraseSpy)

# TRYOUTS

# Setup a customer with argon2 password
@auth_email = generate_unique_test_email("auth_session")
@auth_cust = Customer.create!(email: @auth_email)
@auth_cust.update_passphrase(@testpass)
@auth_cust.save

## Customer has argon2 hash (passphrase_encryption = '2')
@auth_cust.passphrase_encryption
#=> '2'

## Argon2 hash is detected correctly
@auth_cust.argon2_hash?(@auth_cust.passphrase)
#=> true

## Password verification works
@auth_cust.passphrase?(@testpass)
#=> true

## BCrypt password can still be verified (backwards compatibility)
@bcrypt_cust = Customer.create!(email: generate_unique_test_email("bcrypt_migration"))
@bcrypt_cust.passphrase = BCrypt::Password.create('bcrypt-pass-123', cost: 4).to_s
@bcrypt_cust.passphrase_encryption = '1'
@bcrypt_cust.save
@bcrypt_cust.passphrase?('bcrypt-pass-123')
#=> true

## BCrypt hash is not detected as argon2
@bcrypt_cust.argon2_hash?(@bcrypt_cust.passphrase)
#=> false

## BCrypt password can be migrated to argon2
@bcrypt_cust.update_passphrase('bcrypt-pass-123')
@bcrypt_cust.save
@bcrypt_cust.argon2_hash?(@bcrypt_cust.passphrase)
#=> true

## Migrated password still verifies
@bcrypt_cust.passphrase?('bcrypt-pass-123')
#=> true

## Migrated password has encryption mode '2'
@bcrypt_cust.passphrase_encryption
#=> '2'

## Pending-verification login message echoes the email address, not the objid (QS-13)
@pending_email = generate_unique_test_email("pending_login")
@pending_cust = Customer.create!(email: @pending_email)
@pending_cust.update_passphrase(@testpass)
@pending_cust.verified = false
@pending_cust.role = 'customer'
@pending_cust.save
strategy_result = MockStrategyResult.new(session: {})
logic = Auth::AuthenticateSession.new(strategy_result, { 'login' => @pending_email, 'password' => @testpass }, 'en')
logic.raise_concerns
captured = StringIO.new
original_stderr = $stderr
$stderr = captured
begin
  logic.process
ensure
  $stderr = original_stderr
end
msg_line = captured.string.lines.find { |line| line.include?('sent to') }
[msg_line&.include?(@pending_email), msg_line&.include?(@pending_cust.objid)]
#=> [true, false]

# --- #3516: rate-limit lockout gates BEFORE the argon2 comparison ------------
#
# The lockout CHECK moved from raise_concerns into process_params, ahead of the
# `potential.passphrase?(@passwd)` argon2 call. Because process_params fires from
# the Base constructor, a LOCKED subject now raises Onetime::LimitExceeded from
# AuthenticateSession.new(...) itself — before raise_concerns runs, and before any
# customer lookup or password hash is computed. These tests pin that behavior.

## Locked per-IP subject raises LimitExceeded at CONSTRUCTION (the core regression guard)
@locked_email = generate_unique_test_email("locked_login")
@locked_cust  = Customer.create!(email: @locked_email)
@locked_cust.update_passphrase(@testpass)
@locked_cust.save
@locked_ip = '203.0.113.7'
# Lock the tight per-email+IP tier directly via the limiter's Redis key.
Onetime::Customer.dbclient.setex("login:locked:#{@locked_email}:#{@locked_ip}", 1800, '1')
$find_by_email_calls = []
$passphrase_calls    = 0
@locked_strategy = MockStrategyResult.new(session: {}, metadata: { ip: @locked_ip })
begin
  Auth::AuthenticateSession.new(@locked_strategy, { 'login' => @locked_email, 'password' => @testpass }, 'en')
  :no_raise
rescue Onetime::LimitExceeded
  :limit_exceeded
end
#=> :limit_exceeded

## Locked path never reached the customer lookup nor the argon2 comparison
[$find_by_email_calls, $passphrase_calls]
#=> [[], 0]

## Locked NONEXISTENT email also raises at construction, before existence is confirmed (no enumeration delta)
@ghost_email = generate_unique_test_email("ghost_login")
@ghost_ip    = '203.0.113.10'
Onetime::Customer.dbclient.setex("login:locked:#{@ghost_email}:#{@ghost_ip}", 1800, '1')
$find_by_email_calls = []
$passphrase_calls    = 0
@ghost_strategy = MockStrategyResult.new(session: {}, metadata: { ip: @ghost_ip })
outcome = begin
  Auth::AuthenticateSession.new(@ghost_strategy, { 'login' => @ghost_email, 'password' => 'whatever' }, 'en')
  :no_raise
rescue Onetime::LimitExceeded
  :limit_exceeded
end
[outcome, $find_by_email_calls, $passphrase_calls]
#=> [:limit_exceeded, [], 0]

## Happy path (valid creds, not locked) authenticates AND clears prior rate-limit state
@happy_email = generate_unique_test_email("happy_login")
@happy_cust  = Customer.create!(email: @happy_email)
@happy_cust.update_passphrase(@testpass)
@happy_cust.verified = true
@happy_cust.role     = 'customer'
@happy_cust.save
@happy_ip = '203.0.113.8'
# Seed sub-threshold failed-attempt counters on both tiers; a verified login clears them.
Onetime::Customer.dbclient.setex("login:attempts:#{@happy_email}:#{@happy_ip}", 900, '3')
Onetime::Customer.dbclient.setex("login:attempts:#{@happy_email}", 900, '3')
@happy_strategy = MockStrategyResult.new(session: {}, metadata: { ip: @happy_ip })
@happy_logic    = Auth::AuthenticateSession.new(@happy_strategy, { 'login' => @happy_email, 'password' => @testpass }, 'en')
@happy_logic.raise_concerns
captured2 = StringIO.new
orig2     = $stderr
$stderr   = captured2
begin
  @happy_logic.process
ensure
  $stderr = orig2
end
[
  @happy_logic.success?,
  Onetime::Customer.dbclient.get("login:attempts:#{@happy_email}:#{@happy_ip}").nil?,
  Onetime::Customer.dbclient.get("login:attempts:#{@happy_email}").nil?,
]
#=> [true, true, true]

## Wrong password (not locked) RECORDS a failed attempt and raises the non-enumerating error
@wrong_email = generate_unique_test_email("wrong_login")
@wrong_cust  = Customer.create!(email: @wrong_email)
@wrong_cust.update_passphrase(@testpass)
@wrong_cust.save
@wrong_ip = '203.0.113.9'
Onetime::Customer.dbclient.del("login:attempts:#{@wrong_email}:#{@wrong_ip}")
@wrong_strategy = MockStrategyResult.new(session: {}, metadata: { ip: @wrong_ip })
@wrong_logic    = Auth::AuthenticateSession.new(@wrong_strategy, { 'login' => @wrong_email, 'password' => 'definitely-wrong-pass' }, 'en')
err = begin
  @wrong_logic.raise_concerns
  :no_raise
rescue Onetime::FormError => e
  e.message
end
# The per-IP failed-attempt counter incremented to 1, and the generic
# (non-enumerating) message was raised from raise_concerns.
[err.to_s.include?('Invalid email or password'), Onetime::Customer.dbclient.get("login:attempts:#{@wrong_email}:#{@wrong_ip}").to_i]
#=> [true, 1]
