# lib/onetime/models.rb

# This file serves as a central loading point for all model classes across
# different API versions. It provides a convenient way for external code to
# access model classes without needing to understand the underlying version
# structure.
#
# The CURRENT_API_VERSION constant allows test suites and application code to
# reference the current API models without hardcoding specific version
# dependencies throughout the codebase. This facilitates running the same
# test suite against multiple API versions and simplifies version transitions.

require 'v1/models'
require 'v2/models'


module Onetime
  # Points to the current API version's models module.
  # Fixed to V2 for stability, but designed to be configurable in future
  # iterations when dynamic version selection becomes necessary.
  #
  # A fully qualified name example which does not win points for brevity
  # but is easy to read: Onetime::CURRENT_API_VERSION::Customer.
  CURRENT_API_VERSION = V2
end
