# try/api/v1/v1_authentication_enabled_try.rb
#
# frozen_string_literal: true

# Tests that authentication_enabled? (defined in SessionHelpers, inherited
# by V1::ControllerHelpers) uses safe hash access and defaults to enabled
# (true) when config keys are absent.
#
# Regression test for issue #2620 where the previous `rescue false` pattern
# in the V1 override caused API auth to silently fail when config keys were
# missing, returning 404 for valid Basic Auth credentials on POST /api/v1/share.
#
# The override has been removed — V1 now inherits directly from SessionHelpers.
# The `signin` flag is NOT checked, as it controls web login forms, not API
# key authentication.

require_relative '../../support/test_helpers'
OT.boot! :test

# Create a test object that includes the V1 helpers (which includes
# SessionHelpers) to test authentication_enabled? in isolation.
require 'apps/api/v1/controllers/helpers'

class V1AuthTestHarness
  include V1::ControllerHelpers

  # Expose the private method for testing
  public :authentication_enabled?
end

@harness = V1AuthTestHarness.new

# Save original config for restoration
@original_auth = OT.conf['site']['authentication']&.dup

# -----------------------------------------------------------------------
# TEST: authentication_enabled? returns correct values with explicit config
# -----------------------------------------------------------------------

## TC-1: Returns true when authentication.enabled is true
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => true }
@harness.authentication_enabled?
#=> true

## TC-2: Returns false when authentication.enabled is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => false, 'signin' => true }
@harness.authentication_enabled?
#=> false

# -----------------------------------------------------------------------
# TEST: signin flag does NOT gate API authentication (#2620 insight)
# -----------------------------------------------------------------------

## TC-3: Returns true when signin is false but enabled is true
# A deployment may disable web login while keeping the API active.
# The previous V1 override incorrectly returned false here.
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => false }
@harness.authentication_enabled?
#=> true

## TC-4: Returns false only when enabled is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => false, 'signin' => false }
@harness.authentication_enabled?
#=> false

# -----------------------------------------------------------------------
# TEST: Defaults to enabled when config keys are missing (the #2620 fix)
# -----------------------------------------------------------------------

## TC-5: Returns true when authentication hash is missing entirely
OT.conf['site'].delete('authentication')
@harness.authentication_enabled?
#=> true

## TC-6: Returns true when only 'enabled' key is present and true
OT.conf['site']['authentication'] = { 'enabled' => true }
@harness.authentication_enabled?
#=> true

## TC-7: Returns true when authentication hash is empty
OT.conf['site']['authentication'] = {}
@harness.authentication_enabled?
#=> true

## TC-8: Returns true when only 'signin' key is present (enabled absent)
# Missing 'enabled' key defaults to enabled, signin is irrelevant.
OT.conf['site']['authentication'] = { 'signin' => false }
@harness.authentication_enabled?
#=> true

# -----------------------------------------------------------------------
# Restore original config
# -----------------------------------------------------------------------
OT.conf['site']['authentication'] = @original_auth
