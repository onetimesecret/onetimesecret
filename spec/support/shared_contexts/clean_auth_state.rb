# frozen_string_literal: true

# Shared context for cleaning authentication state between test contexts.
#
# This shared context ensures that authentication-related database connections
# and suite-level database setups are properly torn down before a new context
# begins. This is critical for preventing state leaks when switching between
# authentication modes (full, simple, disabled) in the test suite.
#
# Usage:
#   RSpec.describe 'My Test', :full_auth_mode do
#     include_context 'clean_auth_state'
#
#     it 'has a clean slate' do
#       # Database connections and suite databases are reset
#     end
#   end
#
RSpec.shared_context 'clean_auth_state' do
  before(:all) do
    # Teardown any existing suite-level database setups
    # These are lazily initialized and persist across contexts, so we need to
    # explicitly tear them down to prevent cross-contamination
    [FullModeSuiteDatabase, PostgresModeSuiteDatabase].each do |db|
      # Only teardown if the database module is defined AND has been set up
      if defined?(db) && db.respond_to?(:setup_complete?) && db.setup_complete?
        db.teardown!
      end
    end

    # Reset Auth::Database connection to ensure fresh state
    # This is the main authentication database connection that may be cached
    if defined?(Auth::Database)
      if Auth::Database.respond_to?(:reset_connection!)
        Auth::Database.reset_connection!
      else
        # Fallback for older versions without reset_connection! method
        Auth::Database.instance_variable_set(:@connection, nil)
      end
    end
  end
end
