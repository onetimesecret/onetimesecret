# spec/support/shared_contexts/clean_auth_state.rb
#
# frozen_string_literal: true

# This shared context tears down suite-level database setups and resets
# Auth::Database connections to provide a fresh state.
#
# WHEN TO USE:
#   1. Within-mode isolation: When a test file in spec/integration/full/
#      needs to ensure it doesn't inherit state from previous test files
#      in the same RSpec run.
#   2. Explicit fresh state: When a specific test requires a guaranteed
#      clean database connection, independent of run order.
#
# WHEN NOT TO USE:
#   Cross-mode isolation is NOT a valid use case. With directory-based test
#   separation (see ADR-007), each auth mode runs in a separate process:
#     - spec/integration/simple/ runs with AUTHENTICATION_MODE=simple
#     - spec/integration/full/ runs with AUTHENTICATION_MODE=full
#     - spec/integration/disabled/ runs with AUTHENTICATION_MODE=disabled
#   Process boundaries provide complete isolation between modes. Do not use
#   this context to "switch modes" - that's not how the test suite works.
#
# Usage:
#   RSpec.describe 'My Test', type: :integration do
#     include_context 'clean_auth_state'
#
#     it 'starts with fresh database state' do
#       # FullModeSuiteDatabase and Auth::Database are reset
#     end
#   end
#
RSpec.shared_context 'clean_auth_state' do
  before(:all) do
    # Teardown any existing suite-level database setups
    # These are lazily initialized and persist across contexts, so we need to
    # explicitly tear them down to prevent cross-contamination
    #
    # Note: We check Object.const_defined? before referencing the constant,
    # since these modules may not be loaded in all test environments.
    %w[FullModeSuiteDatabase PostgresModeSuiteDatabase].each do |db_name|
      next unless Object.const_defined?(db_name)

      db = Object.const_get(db_name)
      # Only teardown if the database module has been set up
      if db.respond_to?(:setup_complete?) && db.setup_complete?
        begin
          db.teardown!
        rescue => e
          warn "Failed to teardown #{db_name}: #{e.message}"
        end
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
