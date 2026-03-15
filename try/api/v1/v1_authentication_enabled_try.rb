# try/api/v1/v1_authentication_enabled_try.rb
#
# frozen_string_literal: true

# Tests that session_auth_enforced? (defined in SessionHelpers, inherited
# by V1::ControllerHelpers) uses safe hash access via `dig` and defaults
# to DISABLED when config is absent.
#
# Defaulting to disabled is the conservative choice: if config is missing,
# accounts are not used and auth-required features are unavailable. This
# prevents the app from running with unintended auth behavior.
#
# Regression test for issue #2620 where the previous `rescue false` pattern
# in the V1 override silently swallowed config access errors, making it
# impossible to distinguish "config missing" from "config present but key
# absent." The `dig` approach fixes this while preserving the safe default.
#
# The override has been removed — V1 now inherits directly from SessionHelpers.
# The `signin` flag is NOT checked, as it controls web login forms, not API
# key authentication.
#
# Note: This method was renamed from authentication_enabled? to
# session_auth_enforced? to distinguish it from the boot-time
# AuthStrategies.account_creation_allowed? method (see #2620).

require_relative '../../support/test_helpers'
OT.boot! :test

# Create a test object that includes the V1 helpers (which includes
# SessionHelpers) to test session_auth_enforced? in isolation.
require 'apps/api/v1/controllers/helpers'

class V1AuthTestHarness
  include V1::ControllerHelpers

  # Expose the private method for testing
  public :session_auth_enforced?
end

@harness = V1AuthTestHarness.new

# Save original config for restoration
@original_auth = OT.conf['site']['authentication']&.dup

# -----------------------------------------------------------------------
# TEST: session_auth_enforced? returns correct values with explicit config
# -----------------------------------------------------------------------

## TC-1: Returns true when authentication.enabled is true
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => true }
@harness.session_auth_enforced?
#=> true

## TC-2: Returns false when authentication.enabled is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => false, 'signin' => true }
@harness.session_auth_enforced?
#=> false

# -----------------------------------------------------------------------
# TEST: signin flag does NOT gate API authentication (#2620 insight)
# -----------------------------------------------------------------------

## TC-3: Returns true when signin is false but enabled is true
# A deployment may disable web login while keeping the API active.
# The previous V1 override incorrectly returned false here.
OT.conf['site']['authentication'] = { 'enabled' => true, 'signin' => false }
@harness.session_auth_enforced?
#=> true

## TC-4: Returns false only when enabled is explicitly false
OT.conf['site']['authentication'] = { 'enabled' => false, 'signin' => false }
@harness.session_auth_enforced?
#=> false

# -----------------------------------------------------------------------
# TEST: Defaults to DISABLED when config is missing (conservative default)
# -----------------------------------------------------------------------

## TC-5: Returns false when authentication hash is missing entirely
# No auth config → auth disabled → account features unavailable
OT.conf['site'].delete('authentication')
@harness.session_auth_enforced?
#=> false

## TC-6: Returns true when only 'enabled' key is present and true
OT.conf['site']['authentication'] = { 'enabled' => true }
@harness.session_auth_enforced?
#=> true

## TC-7: Returns true when authentication hash exists but 'enabled' key absent
# Auth section present implies intent to use auth; missing 'enabled' key
# is not the same as explicitly disabled.
OT.conf['site']['authentication'] = {}
@harness.session_auth_enforced?
#=> true

## TC-8: Returns true when only 'signin' key is present (enabled absent)
# Auth section present, 'enabled' not explicitly false → enabled.
OT.conf['site']['authentication'] = { 'signin' => false }
@harness.session_auth_enforced?
#=> true

# -----------------------------------------------------------------------
# Restore original config
# -----------------------------------------------------------------------
OT.conf['site']['authentication'] = @original_auth
