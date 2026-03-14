# try/api/v1/v1_authentication_enabled_try.rb
#
# frozen_string_literal: true

# Tests that authentication_enabled? in V1::ControllerHelpers uses safe
# hash access and defaults to enabled (true) when config keys are absent.
#
# This is a regression test for issue #2620 where the previous `rescue false`
# pattern caused API auth to silently fail when config keys were missing,
# returning 404 for valid Basic Auth credentials on POST /api/v1/share.

require_relative '../../support/test_helpers'
OT.boot! :test

# Create a test object that includes the V1 helpers so we can test
# authentication_enabled? in isolation.
require 'apps/api/v1/controllers/helpers'

class V1AuthTestHarness
  include V1::ControllerHelpers
end

@harness = V1AuthTestHarness.new

# Save original config for restoration
@original_conf = OT.conf.dup
@original_site = OT.conf['site'].dup
@original_auth = OT.conf['site']['authentication']&.dup

# -----------------------------------------------------------------------
# TEST: authentication_enabled? returns true with standard config
# -----------------------------------------------------------------------

## TC-1: Returns true when authentication.enabled and authentication.signin are both true
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => true }
@harness.authentication_enabled?
#=> true

## TC-2: Returns false when authentication.enabled is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => false, 'signin' => true }
@harness.authentication_enabled?
#=> false

## TC-3: Returns false when authentication.signin is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => false }
@harness.authentication_enabled?
#=> false

# -----------------------------------------------------------------------
# TEST: Defaults to enabled when config keys are missing (the #2620 fix)
# -----------------------------------------------------------------------

## TC-4: Returns true when authentication hash is missing entirely
OT.conf['site'].delete('authentication')
@harness.authentication_enabled?
#=> true

## TC-5: Returns true when only 'enabled' key is present and true
OT.conf['site']['authentication'] = { 'enabled' => true }
@harness.authentication_enabled?
#=> true

## TC-6: Returns true when only 'signin' key is present and true
OT.conf['site']['authentication'] = { 'signin' => true }
@harness.authentication_enabled?
#=> true

## TC-7: Returns true when authentication hash is empty
OT.conf['site']['authentication'] = {}
@harness.authentication_enabled?
#=> true

# -----------------------------------------------------------------------
# Restore original config
# -----------------------------------------------------------------------
OT.conf['site']['authentication'] = @original_auth
