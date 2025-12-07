# spec/support/shared_contexts/full_mode_database_context.rb
#
# frozen_string_literal: true

# Provides an in-memory SQLite database for full auth mode tests.
# This context sets up the Rodauth schema and stubs Auth::Database.connection.
#
# Usage:
#   RSpec.describe 'My Test', :full_auth_mode do
#     include_context 'full_mode_database'
#
#     it 'has database access' do
#       expect(test_db).to be_a(Sequel::Database)
#     end
#   end
#
RSpec.shared_context 'full_mode_database' do
  let(:test_db) { @test_db }

  before(:all) do
    require 'sequel'
    Sequel.extension :migration

    # Create in-memory SQLite database
    @test_db = Sequel.sqlite

    # Run Rodauth migrations
    # __dir__ = spec/support/shared_contexts, need to go up 3 levels to project root
    migrations_path = File.expand_path('../../../apps/web/auth/migrations', __dir__)
    Sequel::Migrator.run(@test_db, migrations_path)

    # Reset memoized connection and stub with our test database
    Auth::Database.instance_variable_set(:@connection, nil)
  end

  before(:each) do
    # Stub the connection method to return our test database
    allow(Auth::Database).to receive(:connection).and_return(@test_db)
  end

  after(:all) do
    # Clean up
    @test_db&.disconnect
    Auth::Database.instance_variable_set(:@connection, nil)
  end
end
