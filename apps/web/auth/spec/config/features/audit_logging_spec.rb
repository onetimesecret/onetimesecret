# apps/web/auth/spec/config/features/audit_logging_spec.rb
#
# frozen_string_literal: true

# Regression coverage for the alias-once guard in
# Auth::Config::Features::AuditLogging.configure (PR #3915 follow-up, item 6):
# a second configure pass must NOT re-point _original_add_audit_log at the
# already-overridden add_audit_log — that alias would make the override call
# itself, SystemStackError on the first audited event. The double-configure
# path is unreachable through Auth::Config (configure is one-shot behind
# Auth::Config.configured), so this exercises the feature module directly
# against a throwaway Rodauth-shaped class.
#
# RUN:
#   pnpm run test:rspec apps/web/auth/spec/config/features/audit_logging_spec.rb

require 'rspec'

# Define the Auth::Config namespace so the feature module can load without a
# full app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a
# plain module (see omniauth_providers_spec.rb for the TypeError this avoids
# when the real app boots later in the same process).
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)

require File.expand_path('../../../config/features/audit_logging.rb', __dir__)

RSpec.describe 'Auth::Config::Features::AuditLogging double-configure guard' do
  # Fresh per example: the alias guard is per-class state, so a shared class
  # would let one example's configure hide another's regression.
  let(:rodauth_class) do
    Class.new do
      def audit_calls
        @audit_calls ||= []
      end

      def add_audit_log(account_id, action)
        audit_calls << [account_id, action]
      end
    end
  end

  # Null object for the Rodauth configuration DSL (enable, audit_logging_*,
  # audit_log_message_for, ...) — the per-event registrations are keyed and
  # inert here. Only auth_class_eval matters: it lands the logout-guard
  # override (and the alias under test) on the throwaway class.
  let(:configurator) do
    target = rodauth_class
    fake   = double('rodauth configurator').as_null_object
    allow(fake).to receive(:auth_class_eval) { |&blk| target.class_eval(&blk) }
    fake
  end

  def configure!
    Auth::Config::Features::AuditLogging.configure(configurator)
  end

  it 'routes through the original add_audit_log after a single configure' do
    configure!

    instance = rodauth_class.new
    # :login (not :logout) bypasses the orphaned-account guard, so the
    # override delegates straight to the aliased original.
    instance.add_audit_log(7, :login)

    expect(instance.audit_calls).to eq([[7, :login]])
  end

  it 'aliases the original exactly once across two configure passes' do
    configure!
    configure!

    instance = rodauth_class.new
    # Without the alias-once guard the second pass points
    # _original_add_audit_log at the override itself and this recurses to a
    # SystemStackError; with it, the original still runs exactly once.
    expect { instance.add_audit_log(42, :login) }.not_to raise_error
    expect(instance.audit_calls).to eq([[42, :login]])
  end
end
