# try/unit/controllers/v1_auth_hardening_try.rb
#
# frozen_string_literal: true

# Tests for V1 Basic Auth hardening (2026-06-22 assessment P4/P5):
#
#   P4: verify_apitoken performs equivalent work whether or not the
#       username resolved to a customer, so nonexistent-user failures
#       are behaviorally identical to bad-token-for-real-user failures.
#   P5: sanitize_for_log strips control characters (CR/LF/ESC/NUL)
#       before untrusted input is interpolated into log lines.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require_relative '../../../apps/api/v1/controllers/base'

# Mock controller that includes the V1 base module
class ::V1AuthTestController
  include V1::ControllerBase
end

# Stand-in for a loaded Customer; only apitoken? matters here
class ::FakeV1Customer
  def initialize(token)
    @token = token
  end

  def apitoken?(guess)
    Rack::Utils.secure_compare(@token, guess.to_s)
  end
end

@controller = V1AuthTestController.new(nil, nil)
@customer   = FakeV1Customer.new('correct-token-abc123')

# =================================================================
# P4: verify_apitoken
# =================================================================

## Nonexistent user (nil customer) fails auth
@controller.verify_apitoken(nil, 'whatever-token').nil?
#=> true

## Real customer with wrong token fails auth
@controller.verify_apitoken(@customer, 'wrong-token').nil?
#=> true

## Nonexistent-user failure is identical to bad-token failure (both nil)
@controller.verify_apitoken(nil, 'whatever-token') ==
  @controller.verify_apitoken(@customer, 'wrong-token')
#=> true

## Real customer with correct token returns the customer
@controller.verify_apitoken(@customer, 'correct-token-abc123').equal?(@customer)
#=> true

## Nil customer with empty token still fails cleanly (no raise)
@controller.verify_apitoken(nil, '').nil?
#=> true

## Dummy digest is a fixed-length SHA-256 hexdigest
V1::ControllerBase::V1_DUMMY_TOKEN_DIGEST.length
#=> 64

# =================================================================
# P5: sanitize_for_log
# =================================================================

## Strips CR and LF (log-line injection)
@controller.sanitize_for_log("user@example.com\r\n[authorized] forged line")
#=> "user@example.com[authorized] forged line"

## Strips ESC and NUL control characters
@controller.sanitize_for_log("user\e[31m\0name")
#=> "user[31mname"

## Passes normal usernames through unchanged
@controller.sanitize_for_log('user@example.com')
#=> "user@example.com"

## Handles nil without raising
@controller.sanitize_for_log(nil)
#=> ""

## Truncates to 256 characters
@controller.sanitize_for_log('a' * 500).length
#=> 256
