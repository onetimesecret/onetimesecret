# tests/unit/ruby/try/test_models.rb
#
# This file provides convenient access to model classes for testing purposes.
# It creates top-level constants (e.g., Customer) to versioned namespaces
# (e.g., V2::Customer), allowing tests to use cleaner, more readable code
# without version-specific references.
#
# Future improvement: Version selection will be controlled via environment
# variable, enabling the same test suite to run against multiple API versions
# without code changes.

# Make sure the test helpers are loaded before the models. This makes it
# possible for the tryouts to need only one require statement.
require_relative '../helpers/test_helpers'

require 'onetime/models'

# Reference current API version for consistent model access across tests
TestVersion = Onetime::CURRENT_API_VERSION

# Map commonly used models to top-level constants for cleaner test code
Customer = TestVersion::Customer # e.g. V2::Customer
CustomDomain = TestVersion::CustomDomain
Session = TestVersion::Session
Metadata = TestVersion::Metadata
Secret = TestVersion::Secret
EmailReceipt = TestVersion::EmailReceipt
Feedback = TestVersion::Feedback
ExceptionInfo = TestVersion::ExceptionInfo
RateLimit = TestVersion::RateLimit
