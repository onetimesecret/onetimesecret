# apps/api/invite/spec/spec_helper.rb
#
# frozen_string_literal: true

# Start code coverage before any application code loads (see .simplecov).
# Enabled only when COVERAGE=true.
require 'simplecov' if ENV['COVERAGE'] == 'true'

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

# Files these hooks own. See the InviteAuthStubs note below for why the stubs
# are installed per example instead of at load time; the same filter keeps the
# I18n hook at the bottom of this file off other trees' examples.
#
# Filter on :file_path rather than a define_derived_metadata tag: RSpec sets
# :file_path on every example from its own source location, so this holds no
# matter when this helper loads, whereas a derived-metadata rule only reaches
# groups defined after the rule is registered.
INVITE_SPEC_TREE = %r{/apps/api/invite/spec/}

# Test doubles for the auth surfaces the invite logic calls into. These are
# unit specs; the real behaviour is covered by apps/web/auth's own specs.
#
# INSTALLED PER EXAMPLE, ON PURPOSE. These used to be `module Auth ... end
# unless defined?(Auth::Database)` reopenings evaluated at load time, which made
# the winner a function of file load order rather than of intent:
# apps/api/colonel/spec/logic/colonel/get_account_diagnostics_spec.rb requires
# the real 'auth/database', and it sorts before this tree. With one rspec
# process per app spec tree that never happened; the moment the trees share a
# process the guard sees the real Auth::Database, skips this whole block, and
# the invite specs stub methods the real constants do not implement
# (`Auth::Config does not implement: create_account`, x16). stub_const installs
# the same constants deterministically and rspec-mocks restores whatever was
# there before, so neither side can win by accident.
#
# Auth::RestrictTo is deliberately NOT stubbed — the invite logic's restrict_to
# gate is exercised against the real module, and the specs stub only its
# resolution_for/allows? seams.
module InviteAuthStubs
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
    def self.create_account(login:, password:, params: {})
      # Return mock account_id. Real Rodauth internal_request returns nil on
      # success; tests that exercise that contract should override this stub.
      12345
    end
  end

  module Logging
    def self.log_auth_event(*args, **kwargs); end
    def self.log_operation(*args, **kwargs); end
    def self.log_error(*args, **kwargs); end
  end

  # Stub Rodauth::InternalRequestError for unit tests. Both the specs (which
  # raise it) and apps/api/invite/logic/invites/signup_and_accept.rb (which
  # rescues it) resolve the constant at call time, so they agree on whichever
  # class is installed.
  class InternalRequestError < StandardError
    attr_accessor :field_errors, :flash
  end
end

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
  config.include InviteAPITestHelper, file_path: INVITE_SPEC_TREE

  # Install the auth doubles for the duration of each example.
  config.before(:each, file_path: INVITE_SPEC_TREE) do
    stub_const('Auth::Database', InviteAuthStubs::Database)
    stub_const('Auth::Config', InviteAuthStubs::Config)
    stub_const('Auth::Logging', InviteAuthStubs::Logging)
    stub_const('Rodauth::InternalRequestError', InviteAuthStubs::InternalRequestError)
  end

  # Ensure I18n is usable for unit specs that exercise code paths calling
  # I18n.t. Without this, enforce_available_locales! raises InvalidLocale
  # before the default: fallback can kick in. Matches the idiom established
  # in apps/web/core/spec/logic/authentication/authenticate_session_spec.rb.
  #
  # I18n.default_locale is process-global, so this is scoped to this tree
  # rather than left unfiltered.
  config.before(file_path: INVITE_SPEC_TREE) do
    I18n.available_locales = [:en] unless I18n.available_locales.include?(:en)
    I18n.default_locale = :en
  end
end
