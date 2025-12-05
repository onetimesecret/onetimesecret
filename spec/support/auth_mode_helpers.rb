# spec/support/auth_mode_helpers.rb
#
# frozen_string_literal: true

# Helper module for conditionally skipping specs based on authentication mode.
#
# Usage in spec files - two options:
#
# 1. Tag-based (automatic skip via metadata):
#   RSpec.describe 'My Test', :full_auth_mode, type: :integration do
#     # tests here only run when AUTHENTICATION_MODE=full
#   end
#
# 2. Explicit helper method:
#   RSpec.describe 'My Test', type: :integration do
#     skip_unless_mode :full
#     # tests here only run when AUTHENTICATION_MODE=full
#   end
#
module AuthModeHelpers
  VALID_MODES = %w[simple full disabled].freeze

  # Returns the current auth mode
  def self.current_mode
    ENV['AUTHENTICATION_MODE'] || 'unset'
  end

  # Check if current mode matches the required mode
  def self.mode_matches?(required_mode)
    current_mode == required_mode.to_s
  end

  # Class method for use in describe blocks
  def self.skip_unless_mode(required_mode, context)
    unless mode_matches?(required_mode)
      context.before(:all) do
        skip "Requires AUTHENTICATION_MODE=#{required_mode} (current: #{AuthModeHelpers.current_mode})"
      end
    end
  end
end

# Add skip_unless_mode as a class method on RSpec example groups
RSpec.configure do |config|
  # Specs tagged with :full_auth_mode are skipped unless AUTHENTICATION_MODE=full
  config.before(:context, :full_auth_mode) do
    unless AuthModeHelpers.mode_matches?(:full)
      skip "Requires AUTHENTICATION_MODE=full (current: #{AuthModeHelpers.current_mode})"
    end
  end

  # Specs tagged with :simple_auth_mode are skipped unless AUTHENTICATION_MODE=simple
  config.before(:context, :simple_auth_mode) do
    unless AuthModeHelpers.mode_matches?(:simple)
      skip "Requires AUTHENTICATION_MODE=simple (current: #{AuthModeHelpers.current_mode})"
    end
  end

  # Add skip_unless_mode as a DSL method for describe blocks
  config.extend(Module.new do
    def skip_unless_mode(required_mode)
      before(:all) do
        unless AuthModeHelpers.mode_matches?(required_mode)
          skip "Requires AUTHENTICATION_MODE=#{required_mode} (current: #{AuthModeHelpers.current_mode})"
        end
      end
    end

    def skip_if_mode(excluded_mode)
      before(:all) do
        if AuthModeHelpers.mode_matches?(excluded_mode)
          skip "Skipped when AUTHENTICATION_MODE=#{excluded_mode}"
        end
      end
    end
  end)
end
