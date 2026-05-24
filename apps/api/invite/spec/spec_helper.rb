# apps/api/invite/spec/spec_helper.rb
#
# frozen_string_literal: true

# Invite API Test Helper
#
# Run all invite API tests:
#   pnpm run test:rspec apps/api/invite/spec/
#
# Run specific test file:
#   pnpm run test:rspec apps/api/invite/spec/logic/invites/signup_and_accept_spec.rb

# Use the main spec_helper which boots the app
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Load invite API logic
require 'invite/logic'

# Stub Auth modules for unit tests - these are tested in their own specs
module Auth
  module Database
    def self.connection
      # Return a mock Sequel database
      @mock_db ||= begin
        require 'sequel'
        Sequel.mock
      end
    end
  end

  module Config
    def self.create_account(login:, password:)
      # Return mock account_id
      12345
    end
  end

  module Operations
    class CreateCustomer
      def initialize(**args); @args = args; end
      def call; Onetime::Customer.new; end
    end

    class CreateDefaultWorkspace
      def initialize(**args); @args = args; end
      def call; true; end
    end

    class AcceptInvitation
      def initialize(**args); @args = args; end
      def call; { accepted: true, organization_id: 'org-123', role: 'member' }; end
    end
  end

  module Logging
    def self.log_auth_event(*args, **kwargs); end
    def self.log_operation(*args, **kwargs); end
    def self.log_error(*args, **kwargs); end
  end
end unless defined?(Auth::Database)

# Stub Rodauth module for unit tests
module Rodauth
  class InternalRequestError < StandardError
    attr_accessor :field_errors, :flash
  end
end unless defined?(Rodauth::InternalRequestError)

# Shared test helpers for Invite API specs
module InviteAPITestHelper
  # Mock Otto StrategyResult for logic class tests
  def build_strategy_result(session: {}, user: nil, authenticated: false, metadata: {})
    double('StrategyResult',
      session: session,
      user: user,
      authenticated?: authenticated,
      metadata: metadata,
      # Additional methods used by logic base class
      auth_method: nil,
      request: nil,
      locale: 'en'
    )
  end

  # Build a mock customer
  def build_mock_customer(attrs = {})
    defaults = {
      objid: "cust-#{SecureRandom.hex(4)}",
      custid: "cust-#{SecureRandom.hex(4)}",
      extid: "ext-#{SecureRandom.hex(4)}",
      email: "test-#{SecureRandom.hex(4)}@example.com",
      anonymous?: false,
      verified?: false,
      obscure_email: 'te***@example.com'
    }
    instance_double(Onetime::Customer, defaults.merge(attrs))
  end

  # Build a mock organization
  def build_mock_organization(attrs = {})
    defaults = {
      objid: "org-#{SecureRandom.hex(4)}",
      extid: "org-ext-#{SecureRandom.hex(4)}",
      display_name: 'Test Organization',
      'member?' => false
    }
    instance_double(Onetime::Organization, defaults.merge(attrs))
  end

  # Build a mock invitation (OrganizationMembership in pending state)
  def build_mock_invitation(attrs = {})
    defaults = {
      objid: "inv-#{SecureRandom.hex(4)}",
      token: SecureRandom.hex(24),
      invited_email: "invitee-#{SecureRandom.hex(4)}@example.com",
      role: 'member',
      status: 'pending',
      'pending?' => true,
      'expired?' => false,
      'active?' => false,
      organization: nil, # Set by caller
      organization_objid: nil, # Set by caller
      invited_by: nil,
      joined_at: nil,
      invitation_expires_at: (Time.now + 7 * 24 * 60 * 60).to_i
    }
    instance_double(Onetime::OrganizationMembership, defaults.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include InviteAPITestHelper

  # Ensure I18n is usable for unit specs that exercise code paths calling
  # I18n.t. Without this, enforce_available_locales! raises InvalidLocale
  # before the default: fallback can kick in. Matches the idiom established
  # in apps/web/core/spec/logic/authentication/authenticate_session_spec.rb.
  config.before do
    I18n.available_locales = [:en] unless I18n.available_locales.include?(:en)
    I18n.default_locale = :en
  end
end
