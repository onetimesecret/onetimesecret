# tests/unit/ruby/rspec/support/migration_context.rb
#
# Shared context for migration tests providing common setup and logging suppression
#

RSpec.shared_context "migration_test_context" do
  # Suppress migration logging during tests since we're testing logic, not output
  before do
    allow(OT).to receive(:li).and_return(nil)
    allow(OT).to receive(:ld).and_return(nil)
    allow(OT).to receive(:le).and_return(nil)
    allow(OT).to receive(:lw).and_return(nil)
  end

  # Common option hashes for testing run modes
  let(:dry_run_options) { { run: false } }
  let(:actual_run_options) { { run: true } }
end
